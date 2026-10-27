// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { CashTradingFixture } from "./CashTrading.t.sol";
import { OpenParams, ClaimPortion } from "../../src/types/TradingTypes.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";

contract EconomicSnapshotsTest is CashTradingFixture {
    function test_NewPresetAndFeeVersionCannotRewriteExistingTrade() public {
        vm.prank(alice);
        uint256 original = trading.openPosition(1, _params(true), new ClaimPortion[](0), new bytes[](0));
        bytes32 originalTerms = keccak256(abi.encode(trading.economicTerms(MARKET, 1)));
        LibTrades.Trade memory old = trading.tradeState(original);
        LibMarkets.Terms memory next = _terms();
        next.curve.alternate = true;
        next.fees.winStakerBps = 200;
        next.liquidationBufferWad = 1e14;
        trading.publishTerms(MARKET, next);
        assertEq(keccak256(abi.encode(trading.economicTerms(MARKET, 1))), originalTerms);
        assertEq(keccak256(abi.encode(trading.tradeState(original))), keccak256(abi.encode(old)));
        vm.prank(alice);
        vm.expectRevert(LibMarkets.TermsChanged.selector);
        trading.openPosition(1, _params(true), new ClaimPortion[](0), new bytes[](0));
        OpenParams memory p = _params(true);
        p.expectedTermsVersion = 2;
        vm.prank(alice);
        uint256 fresh = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        assertEq(trading.tradeState(fresh).termsVersion, 2);
        assertLt(trading.tradeState(fresh).bustPrice1e18, old.bustPrice1e18);
        assertEq(trading.economicTerms(MARKET, 1).fees.winStakerBps, 100);
        assertEq(trading.economicTerms(MARKET, 2).fees.winStakerBps, 200);
        assertFalse(trading.economicTerms(MARKET, 1).curve.alternate);
        assertTrue(trading.economicTerms(MARKET, 2).curve.alternate);
    }

    function test_LoweredAndDisabledAdmissionDoesNotBlockOnceOnlyExposureRelease() public {
        vm.prank(alice);
        uint256 id = trading.openPosition(1, _params(false), new ClaimPortion[](0), new bytes[](0));
        LibMarkets.Risk memory r = _risk();
        r.maxLeverage = 2;
        r.maxShortOiWad = 1;
        r.maxTotalOiWad = 1;
        r.opensEnabled = false;
        r.enabled = false;
        trading.configureMarket(MARKET, STREAM, r);
        trading.setGlobalOiCap(1);
        vm.prank(alice);
        trading.retireFlat(1, id);
        assertEq(trading.marketState(MARKET).shortOiWad, 0);
        (uint256 oi,) = trading.globalOpenInterest();
        assertEq(oi, 0);
        assertEq(trading.accountState(1).openTradeCount, 0);
        assertEq(trading.book().lockedCashMarginWad, 0);
        assertEq(trading.book().accountCashWad, 1_000e18);
        vm.prank(alice);
        vm.expectRevert(LibTrades.AlreadySettled.selector);
        trading.retireFlat(1, id);
        assertEq(trading.book().accountCashWad, 1_000e18);
    }

    function test_ChangingCapsDoesNotAlterOtherSideOrTradeOwnership() public {
        vm.startPrank(alice);
        uint256 longId = trading.openPosition(1, _params(true), new ClaimPortion[](0), new bytes[](0));
        uint256 shortId = trading.openPosition(1, _params(false), new ClaimPortion[](0), new bytes[](0));
        statics.transferFrom(alice, bob, 1);
        vm.stopPrank();
        LibMarkets.Risk memory r = _risk();
        r.maxLongOiWad = 1;
        trading.configureMarket(MARKET, STREAM, r);
        vm.prank(bob);
        trading.retireFlat(1, longId);
        assertEq(trading.marketState(MARKET).longOiWad, 0);
        assertEq(trading.marketState(MARKET).shortOiWad, 10_000e18);
        vm.prank(bob);
        trading.retireFlat(1, shortId);
        assertEq(trading.accountState(1).cashWad, 1_000e18);
    }
}
