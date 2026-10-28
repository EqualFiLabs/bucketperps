// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StakingProtocolFixture } from "../helpers/StakingProtocolFixture.sol";
import { LedgerVectorsTest } from "../reference/LedgerVectors.t.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { LibQueue } from "../../src/libraries/LibQueue.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";
import { LibFees } from "../../src/libraries/LibFees.sol";
import { LibStakingStorage } from "../../src/libraries/LibStakingStorage.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibSettlement } from "../../src/libraries/LibSettlement.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { OpenParams, ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

/// @dev Seeds independent preconditions only. All transitions run through production facets.
contract LedgerSeedFacet {
    function seed(LedgerVectorsTest.Vector calldata row, bytes32 marketId) external {
        LibGuard.enter();
        LibBookStorage.State storage b = LibBookStorage.state();
        CashTokenMock token = CashTokenMock(b.settlementToken);
        token.burn(address(this), token.balanceOf(address(this)));
        token.mint(address(this), row.beforeBook.t / b.cashQuantum);
        _book(row.beforeBook);
        // Existing fixture accounts initially contain cash only; remove those fixture legs first.
        delete LibAccountsStorage.state().accounts[1];
        delete LibAccountsStorage.state().accounts[2];
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[1];
        a.cashWad = row.beforeBook.c;
        a.committedClaimMarginWad = row.beforeBook.d;
        // Existing fixture legs remain active. They cannot be detached by these replay preconditions.
        a.externalStateActive = true;
        LibAccountsStorage.state().accounts[2].externalStateActive = true;
        bytes32 kind = keccak256(bytes(row.kind));
        _queue(row, kind);
        if (row.beforeBook.m != 0 || row.beforeBook.d != 0) _trade(row, marketId, kind);
        if (kind == keccak256("feeCredit")) {
            a.claimableRevenueWad = row.amount;
            LibFees.state().stakerPayableWad = row.beforeBook.f;
        } else {
            LibFees.state().protocolPayableWad = row.beforeBook.f;
        }
        bool zeroWeight = row.retainedStaker != 0;
        // Positive denominator is a fee-allocation precondition, not real staking qualification.
        LibStakingStorage.state().totalEffectiveWeight = zeroWeight ? 0 : 1;
        LibGuard.exit();
    }

    function _book(LedgerVectorsTest.Book calldata x) private {
        LibBookStorage.State storage b = LibBookStorage.state();
        b.custodyWad = x.t;
        b.accountCashWad = x.c;
        b.lockedCashMarginWad = x.m;
        b.fundedPayablesWad = x.f;
        b.sideBucketWad = x.s;
        b.queuedDebtWad = x.q;
        b.committedDebtWad = x.d;
        b.realizedHousePnlWad = x.p;
    }

    function _queue(LedgerVectorsTest.Vector calldata row, bytes32 kind) private {
        if (row.beforeBook.q == 0) return;
        LibQueue.State storage q = LibQueue.state();
        uint256 first = kind == keccak256("harvest") ? row.amount : row.beforeBook.q;
        q.headId = 1;
        q.nextClaimId = 1;
        q.claims[1] = LibQueue.Claim(1, first);
        q.accountClaimIds[1].push(1);
        LibAccountsStorage.state().accounts[1].liveClaimCount = 1;
        if (first < row.beforeBook.q) {
            q.nextClaimId = 2;
            q.claims[2] = LibQueue.Claim(1, row.beforeBook.q - first);
            q.accountClaimIds[1].push(2);
            ++LibAccountsStorage.state().accounts[1].liveClaimCount;
        }
    }

    function _trade(LedgerVectorsTest.Vector calldata row, bytes32 marketId, bytes32 kind) private {
        bool cash = row.beforeBook.m != 0;
        uint256 margin = cash ? row.beforeBook.m : row.beforeBook.d;
        LibTrades.Trade storage t = LibTrades.state().trades[1];
        LibTrades.state().nextTradeId = 1;
        t.positionId = 1;
        t.marketId = marketId;
        t.streamId = LibMarkets.state().markets[marketId].streamId;
        t.fundingSource = cash ? FundingSource.Cash : FundingSource.Claim;
        t.isLong = true;
        t.marginWad = margin;
        t.leverage = 100;
        t.notionalWad = margin * 100;
        t.entryPrice1e18 = 50_000e18;
        t.bustPrice1e18 = LibPnl.bustPrice(50_000e18, 100, 5e14, true);
        t.termsVersion = 1;
        t.openedAt = uint64(block.timestamp);
        LibMarkets.state().markets[marketId].longOiWad = t.notionalWad;
        LibMarkets.state().globalOiWad = t.notionalWad;
        LibAccountsStorage.state().accounts[1].openTradeCount = 1;
        if (kind == keccak256("cashWin") || kind == keccak256("claimWin")) {
            LibMarkets.state().versions[marketId][1].curve = _curveFor(margin, row.basis);
        }
    }

    // Choose a valid fixture curve that yields the independent vector's quantized profit.
    // This calibrates only the price/PnL precondition; expected ledger changes remain untouched.
    function _curveFor(uint256 margin, uint256 target) private pure returns (LibPnl.Curve memory c) {
        c = LibPnl.Curve(0, 1e27, 1e18, 0, false);
        uint256 low;
        uint256 high = 1e18;
        while (low < high) {
            uint256 middle = (low + high) / 2;
            c.baseRateWad = middle;
            (, int256 profit) = LibPnl.calculate(LibPnl.Position(50_000e18, 100_000e18, margin, 100, true), c);
            if (uint256(profit) / 1e12 * 1e12 > target) low = middle + 1;
            else high = middle;
        }
        c.baseRateWad = low;
    }
}

contract LedgerReplayTest is StakingProtocolFixture {
    function test_TwentyIndependentTransitionsMatchProductionBook() public {
        LedgerVectorsTest.Vector[] memory rows = abi.decode(
            vm.parseJson(vm.readFile("test/fixtures/ledger-vectors.json"), ".vectors"),
            (LedgerVectorsTest.Vector[])
        );
        LedgerSeedFacet seeder = new LedgerSeedFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = LedgerSeedFacet.seed.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = _cut(address(seeder), selectors);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        uint256 checked;
        for (uint256 i; i < rows.length; ++i) {
            bytes32 kind = keccak256(bytes(rows[i].kind));
            uint256 snapshot = vm.snapshotState();
            LedgerSeedFacet(address(diamond)).seed(rows[i], MARKET);
            _execute(rows[i], kind);
            _assertBook(rows[i].afterBook, rows[i].id);
            assertTrue(vm.revertToState(snapshot));
            ++checked;
        }
        assertEq(checked, 20);
    }

    function _execute(LedgerVectorsTest.Vector memory r, bytes32 kind) private {
        if (kind == keccak256("feeCredit")) {
            vm.prank(alice);
            assertEq(staking.claimStakerRevenue(1), r.amount, r.id);
        } else if (kind == keccak256("claimOpen")) {
            OpenParams memory p = _params(true, FundingSource.Claim);
            p.marginWad = r.amount;
            ClaimPortion[] memory portions = new ClaimPortion[](1);
            portions[0] = ClaimPortion(1, r.amount);
            vm.prank(alice);
            trading.openPosition(1, p, portions, new bytes[](0));
        } else if (kind == keccak256("harvest")) {
            assertEq(queue.harvest(1), r.amount, r.id);
        } else if (kind == keccak256("feeDelivery")) {
            feeFacet.withdrawProtocolFees(r.amount, bob);
        } else if (kind == keccak256("surplus")) {
            houseFacet.distributeSurplus(r.amount);
        } else {
            LibTrades.Trade memory t = trading.tradeState(1);
            if (kind == keccak256("cashWin") || kind == keccak256("claimWin")) _price(100_000e18);
            else if (kind == keccak256("claimFlat")) _price(t.entryPrice1e18);
            else if (r.basis == t.marginWad) _price(t.bustPrice1e18);
            else _price(t.entryPrice1e18 - r.basis * t.entryPrice1e18 / t.notionalWad);
            vm.prank(alice);
            LibSettlement.Result memory result =
                settlement.closePosition(1, 1, block.timestamp, new bytes[](0));
            if (kind == keccak256("cashWin") || kind == keccak256("claimWin")) {
                assertEq(result.profitWad, r.basis, r.id);
            } else {
                assertEq(result.lossWad, r.basis, r.id);
            }
            assertEq(result.fundedFeeWad, r.fundedFee, r.id);
        }
    }

    function _assertBook(LedgerVectorsTest.Book memory x, string memory label) private view {
        LibBookStorage.State memory b = bookView.book();
        assertEq(b.custodyWad, x.t, label);
        assertEq(b.accountCashWad, x.c, label);
        assertEq(b.lockedCashMarginWad, x.m, label);
        assertEq(b.fundedPayablesWad, x.f, label);
        assertEq(b.sideBucketWad, x.s, label);
        assertEq(b.queuedDebtWad, x.q, label);
        assertEq(b.committedDebtWad, x.d, label);
        assertEq(b.realizedHousePnlWad, x.p, label);
        assertEq(b.custodyWad - b.accountCashWad - b.lockedCashMarginWad - b.fundedPayablesWad, x.h, label);
    }
}
