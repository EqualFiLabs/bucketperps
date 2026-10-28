// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibFees } from "../../src/libraries/LibFees.sol";
import { LibRewards } from "../../src/libraries/LibRewards.sol";
import { BucketRewardToken } from "../../src/rewards/BucketRewardToken.sol";
import { ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

contract ProtocolHandler is ControlProtocolFixture {
    uint256[] internal opened;
    uint256 public successfulOpens;
    uint256 public successfulSettlements;
    uint256 public successfulTransfers;

    function open(uint256 actor, bool claimFunded, bool isLong) external {
        uint256 id = actor % 2 + 1;
        address owner = statics.ownerOf(id);
        _price(50_000e18);
        if (claimFunded) {
            (uint256 head, uint256 last,) = queue.queueState();
            if (last < head) return;
            uint256 candidate = head + actor % (last - head + 1);
            if (
                queue.claimState(candidate).positionId != id
                    || queue.claimState(candidate).remainingWad < 100e18
            ) return;
            ClaimPortion[] memory portions = new ClaimPortion[](1);
            portions[0] = ClaimPortion(candidate, 100e18);
            vm.prank(owner);
            opened.push(
                trading.openPosition(id, _params(isLong, FundingSource.Claim), portions, new bytes[](0))
            );
        } else {
            if (accounts.accountState(id).cashWad < 100e18) return;
            opened.push(_openCash(id, owner, isLong));
        }
        ++successfulOpens;
    }

    function settle(uint256 pick, uint256 outcome, bool publicBust) external {
        if (opened.length == 0) return;
        uint256 tradeId = opened[pick % opened.length];
        LibTrades.Trade memory t = trading.tradeState(tradeId);
        if (t.settled) return;
        if (publicBust) {
            _price(t.isLong ? 1e18 : 100_000e18);
            liquidation.liquidate(t.positionId, tradeId, new bytes[](0));
        } else {
            uint256[4] memory prices = [uint256(49_900e18), 50_500e18, 50_000e18, 49_000e18];
            _price(prices[outcome % 4]);
            vm.prank(statics.ownerOf(t.positionId));
            settlement.closePosition(t.positionId, tradeId, block.timestamp, new bytes[](0));
        }
        ++successfulSettlements;
    }

    function depositCash(uint256 actor, uint64 amount) external {
        uint256 id = actor % 2 + 1;
        _deposit(statics.ownerOf(id), id, bound(amount, 1, 1000e6));
    }

    function harvest(uint256 count) external {
        queue.harvest(bound(count, 1, 128));
    }

    function rewardPhase(uint96 amount, uint64 rate) external {
        _inventory(bound(amount, 1, 100e18));
        rewards.setLossRewardRate(bound(rate, 0, 5e18));
    }

    function stakeChange(uint256 actor, uint96 units, bool remove) external {
        uint256 id = actor % 2 + 1;
        LibAccountsStorage.Account memory a = accounts.accountState(id);
        uint256 available = remove ? a.rawStakeUnits : a.unstakedRewardUnits;
        if (available == 0) return;
        uint256 n = bound(units, 1, available);
        vm.prank(statics.ownerOf(id));
        if (remove) staking.unstake(id, n);
        else staking.stake(id, n);
    }

    function claimRevenue(uint256 actor) external {
        uint256 id = actor % 2 + 1;
        vm.prank(statics.ownerOf(id));
        staking.claimStakerRevenue(id);
    }

    function transferAccount(uint256 actor) external {
        uint256 id = actor % 2 + 1;
        address owner = statics.ownerOf(id);
        address next = owner == alice ? bob : alice;
        vm.prank(owner);
        statics.transferFrom(owner, next, id);
        ++successfulTransfers;
    }

    function canonicalWeight(uint256 actor, uint16 multiplier) external {
        statics.changeMultiplier(address(diamond), actor % 2 + 1, bound(multiplier, 10_000, 30_000));
    }

    function oracleFailure(uint256 actor) external {
        uint256 id = actor % 2 + 1;
        if (accounts.accountState(id).cashWad < 100e18) return;
        bytes32 beforeBook = keccak256(abi.encode(bookView.book()));
        oracle.setFailure(abi.encodeWithSignature("Error(string)", "injected"));
        vm.prank(statics.ownerOf(id));
        try trading.openPosition(
            id, _params(true, FundingSource.Cash), new ClaimPortion[](0), new bytes[](0)
        ) returns (
            uint256
        ) {
            revert("failure accepted");
        } catch { }
        oracle.setFailure("");
        assertEq(keccak256(abi.encode(bookView.book())), beforeBook);
    }

    function checkConservation() external view {
        LibBookStorage.State memory b = bookView.book();
        LibAccountsStorage.Account memory a = accounts.accountState(1);
        LibAccountsStorage.Account memory c = accounts.accountState(2);
        assertEq(b.custodyWad, token.balanceOf(address(diamond)) * b.cashQuantum);
        assertEq(b.accountCashWad, a.cashWad + c.cashWad);
        assertEq(b.committedDebtWad, a.committedClaimMarginWad + c.committedClaimMarginWad);
        assertGe(b.custodyWad, b.accountCashWad + b.lockedCashMarginWad + b.fundedPayablesWad);
        assertLe(
            b.sideBucketWad, b.custodyWad - b.accountCashWad - b.lockedCashMarginWad - b.fundedPayablesWad
        );
        LibFees.State memory f = feeFacet.feePayables();
        assertEq(
            b.fundedPayablesWad,
            f.protocolPayableWad + f.operatorPayableWad + f.stakerPayableWad
                + liquidation.totalKeeperPayable()
        );
        _checkTrades(b);
        _checkRewards(a, c, f.stakerPayableWad);
    }

    function _checkTrades(LibBookStorage.State memory b) private view {
        uint256 locked;
        uint256 committed;
        uint256 oi;
        uint256 liveOne;
        uint256 liveTwo;
        for (uint256 i; i < opened.length; ++i) {
            LibTrades.Trade memory t = trading.tradeState(opened[i]);
            if (t.settled) continue;
            oi += t.notionalWad;
            if (t.fundingSource == FundingSource.Cash) locked += t.marginWad;
            else committed += t.marginWad;
            if (t.positionId == 1) ++liveOne;
            else ++liveTwo;
        }
        assertEq(b.lockedCashMarginWad, locked);
        assertEq(b.committedDebtWad, committed);
        assertEq(accounts.accountState(1).openTradeCount, liveOne);
        assertEq(accounts.accountState(2).openTradeCount, liveTwo);
        (uint256 actualOi,) = markets.globalOpenInterest();
        assertEq(oi, actualOi);
        (, uint256 last,) = queue.queueState();
        uint256 debt;
        for (uint256 i = 1; i <= last; ++i) {
            debt += queue.claimState(i).remainingWad;
        }
        assertEq(debt, b.queuedDebtWad);
    }

    function _checkRewards(
        LibAccountsStorage.Account memory a,
        LibAccountsStorage.Account memory c,
        uint256 stakerPayable
    ) private view {
        LibRewards.State memory r = rewards.rewardState();
        uint256 receipt = a.unstakedRewardUnits + c.unstakedRewardUnits + a.rawStakeUnits + c.rawStakeUnits;
        assertEq(receipt, BucketRewardToken(r.receipt).totalSupply());
        assertEq(receipt, r.allocatedUnits);
        assertEq(r.allocatedUnits, staticsToken.balanceOf(r.backingVault));
        assertEq(r.inventoryUnits, staticsToken.balanceOf(address(diamond)));
        (uint256 raw, uint256 weight,,) = staking.stakingTotals();
        assertEq(raw, a.rawStakeUnits + c.rawStakeUnits);
        assertEq(weight, a.effectiveWeight + c.effectiveWeight);
        assertLe(staking.pendingStakerRevenue(1) + staking.pendingStakerRevenue(2), stakerPayable);
    }
}

contract ProtocolStatefulTest is StdInvariant, Test {
    ProtocolHandler internal h;

    function setUp() public {
        h = new ProtocolHandler();
        h.setUp();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = h.open.selector;
        selectors[1] = h.settle.selector;
        selectors[2] = h.depositCash.selector;
        selectors[3] = h.harvest.selector;
        selectors[4] = h.rewardPhase.selector;
        selectors[5] = h.stakeChange.selector;
        selectors[6] = h.claimRevenue.selector;
        selectors[7] = h.transferAccount.selector;
        selectors[8] = h.canonicalWeight.selector;
        selectors[9] = h.oracleFailure.selector;
        targetContract(address(h));
        targetSelector(FuzzSelector(address(h), selectors));
    }

    function invariantAllLedgersAndAuthorityRemainConserved() public view {
        h.checkConservation();
    }
}
