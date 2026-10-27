// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { OpenParams, ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

contract LiquidationEconomicsTest is ProtocolFixture {
    function test_OwnerMaySelfLiquidateWithoutIncreasingFundedFee() public {
        uint256 id = _openCash(1, alice, true);
        _price(trading.tradeState(id).bustPrice1e18);
        vm.prank(alice);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(alice), 0.4e18);
        assertEq(bookView.book().fundedPayablesWad, 1e18);
        assertEq(
            feeFacet.feePayables().protocolPayableWad + feeFacet.feePayables().operatorPayableWad
                + liquidation.totalKeeperPayable(),
            bookView.book().fundedPayablesWad
        );
        assertEq(bookView.book().realizedHousePnlWad, 99e18);
    }

    function test_SnapshottedKeeperTermsSurviveNewZeroRateAndDisabledMarket() public {
        uint256 id = _openCash(1, alice, true);
        LibMarkets.Terms memory next = _terms();
        next.fees.keeperLossBps = 0;
        next.fees.keeperMaxWad = 0;
        markets.publishTerms(MARKET, next);
        LibMarkets.Risk memory risk = _risk();
        risk.enabled = false;
        risk.opensEnabled = false;
        markets.configureMarket(MARKET, STREAM, risk);
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(address(this)), 0.4e18);
        assertEq(accounts.accountState(1).openTradeCount, 0);
    }

    function test_AbsoluteCapAndZeroRateBothConstrainNewLiquidations() public {
        LibMarkets.Terms memory capped = _terms();
        capped.fees.keeperMaxWad = 0.1e18;
        markets.publishTerms(MARKET, capped);
        OpenParams memory p = _params(true, FundingSource.Cash);
        p.expectedTermsVersion = 2;
        vm.prank(alice);
        uint256 id = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(address(this)), 0.1e18);
        capped.fees.keeperLossBps = 0;
        markets.publishTerms(MARKET, capped);
        p.expectedTermsVersion = 3;
        _price(50_000e18);
        vm.prank(alice);
        id = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(address(this)), 0.1e18);
    }

    function test_MinimumQuantumTradeCanLiquidateWithNoFeeOrBounty() public {
        LibMarkets.Risk memory risk = _risk();
        risk.minMarginWad = 1e12;
        risk.minNotionalWad = 1e12;
        markets.configureMarket(MARKET, STREAM, risk);
        OpenParams memory p = _params(true, FundingSource.Cash);
        p.marginWad = 1e12;
        vm.prank(alice);
        uint256 id = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(bookView.book().fundedPayablesWad, 0);
        assertEq(liquidation.totalKeeperPayable(), 0);
        assertTrue(trading.tradeState(id).settled);
    }

    function test_ZeroBountyExecutionHasBoundedFixtureWork() public {
        bookView.seedEntitlement(2, 100e18);
        uint256 id = _openCash(1, alice, true);
        _price(trading.tradeState(id).bustPrice1e18);
        uint256 before = gasleft();
        liquidation.liquidate(1, id, new bytes[](0));
        uint256 used = before - gasleft();
        emit log_named_uint("mock-adapter liquidation gas", used);
        assertLt(used, 1_500_000);
        assertEq(liquidation.totalKeeperPayable(), 0);
        assertTrue(trading.tradeState(id).settled);
        // This bound excludes real report verification, billing and sequencer operation.
    }
}
