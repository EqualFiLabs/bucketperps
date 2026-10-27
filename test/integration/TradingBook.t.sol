// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { LibSettlement } from "../../src/libraries/LibSettlement.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { CashFacet } from "../../src/facets/CashFacet.sol";
import { OpenParams, ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

contract TradingBookAcceptanceTest is ProtocolFixture {
    uint256 internal lastTrade;

    function test_ZeroHouseOpposingTradesClaimReuseAndNftSaleReconcileEveryStep() public {
        _check();
        uint256 longId = _openCash(1, alice, true);
        lastTrade = longId;
        _check();
        uint256 shortId = _openCash(2, bob, false);
        lastTrade = shortId;
        _check();
        _price(55_000e18);
        vm.prank(alice);
        LibSettlement.Result memory win = settlement.closePosition(1, longId, block.timestamp, new bytes[](0));
        assertGt(win.netProfitWad, 1e18);
        assertEq(win.fundedFeeWad, 0);
        _check();
        liquidation.liquidate(2, shortId, new bytes[](0));
        assertEq(liquidation.totalKeeperPayable(), 0);
        assertEq(bookView.book().sideBucketWad, 100e18);
        _check();
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(win.entitlement.claimId, win.netProfitWad);
        OpenParams memory p = _params(true, FundingSource.Claim);
        p.marginWad = win.netProfitWad;
        p.leverage = 2;
        vm.prank(alice);
        uint256 reused = trading.openPosition(1, p, portions, new bytes[](0));
        lastTrade = reused;
        assertEq(bookView.book().sideBucketWad, 0);
        assertEq(bookView.book().queuedDebtWad, 0);
        _check();
        LibMarkets.Terms memory next = _terms();
        next.curve.alternate = true;
        next.fees.lossStakerBps = 500;
        markets.publishTerms(MARKET, next);
        LibMarkets.Risk memory r = _risk();
        r.maxTotalOiWad = 1;
        r.maxLongOiWad = 1;
        markets.configureMarket(MARKET, STREAM, r);
        markets.setGlobalOiCap(1);
        address buyer = makeAddr("buyer");
        vm.prank(alice);
        statics.transferFrom(alice, buyer, 1);
        _check();
        vm.prank(alice);
        vm.expectRevert();
        settlement.closePosition(1, reused, block.timestamp, new bytes[](0));
        vm.prank(buyer);
        LibSettlement.Result memory flat =
            settlement.closePosition(1, reused, block.timestamp, new bytes[](0));
        assertEq(flat.entitlement.paidWad, win.netProfitWad);
        assertEq(flat.quotedFeeWad, 0);
        _check();
        uint256 cashWad = accounts.accountState(1).cashWad;
        vm.prank(buyer);
        cash.withdraw(1, cashWad, buyer);
        _check();
        assertEq(statics.activeLegCount(1), 0);
        vm.prank(buyer);
        statics.close(1);
        _check();
    }

    function test_HostileCrossFacetCallbackCannotPartiallySettleTheBook() public {
        uint256 id = _openCash(1, alice, true);
        lastTrade = id;
        bytes32 beforeBook = keccak256(abi.encode(bookView.book()));
        oracle.setCallback(address(diamond), abi.encodeCall(CashFacet.withdraw, (1, 100e18, alice)));
        _price(49_900e18);
        vm.prank(alice);
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(keccak256(abi.encode(bookView.book())), beforeBook);
        assertFalse(trading.tradeState(id).settled);
        _check();
    }

    function _check() private view {
        LibBookStorage.State memory b = bookView.book();
        LibAccountsStorage.Account memory a = accounts.accountState(1);
        LibAccountsStorage.Account memory c = accounts.accountState(2);
        assertEq(b.accountCashWad, a.cashWad + c.cashWad);
        assertEq(b.committedDebtWad, a.committedClaimMarginWad + c.committedClaimMarginWad);
        uint256 cashMargin;
        uint256 debtMargin;
        uint256 oi;
        uint256 liveTrades;
        for (uint256 i = 1; i <= lastTrade; ++i) {
            LibTrades.Trade memory t = trading.tradeState(i);
            if (t.settled) continue;
            ++liveTrades;
            oi += t.notionalWad;
            if (t.fundingSource == FundingSource.Cash) cashMargin += t.marginWad;
            else debtMargin += t.marginWad;
        }
        assertEq(cashMargin, b.lockedCashMarginWad);
        assertEq(debtMargin, b.committedDebtWad);
        assertEq(liveTrades, a.openTradeCount + c.openTradeCount);
        (uint256 actualOi,) = markets.globalOpenInterest();
        assertEq(oi, actualOi);
        (, uint256 lastClaim,) = queue.queueState();
        uint256 debt;
        uint256 liveClaims;
        for (uint256 i = 1; i <= lastClaim; ++i) {
            uint256 remaining = queue.claimState(i).remainingWad;
            debt += remaining;
            if (remaining != 0) ++liveClaims;
        }
        assertEq(debt, b.queuedDebtWad);
        assertEq(liveClaims, a.liveClaimCount + c.liveClaimCount);
        assertEq(
            b.fundedPayablesWad,
            feeFacet.feePayables().protocolPayableWad + feeFacet.feePayables().operatorPayableWad
                + feeFacet.feePayables().stakerPayableWad + liquidation.totalKeeperPayable()
        );
        uint256 house = b.custodyWad - b.accountCashWad - b.lockedCashMarginWad - b.fundedPayablesWad;
        assertLe(b.sideBucketWad, house);
        if (b.queuedDebtWad == 0) assertEq(b.sideBucketWad, 0);
        assertEq(int256(house) - int256(b.queuedDebtWad) - int256(b.committedDebtWad), b.realizedHousePnlWad);
        assertEq(token.balanceOf(address(diamond)) * 1e12, b.custodyWad);
    }
}
