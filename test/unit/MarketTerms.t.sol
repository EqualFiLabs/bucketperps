// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { MarketFacet } from "../../src/facets/MarketFacet.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";

contract MarketHarness is MarketFacet {
    constructor() {
        LibProtocol.initialize(msg.sender, msg.sender, 1 days);
    }

    function admit(bytes32 id, uint64 version, uint256 margin, uint32 leverage, bool isLong) external {
        LibMarkets.admit(id, version, margin, leverage, isLong);
    }
}

contract MarketTermsTest is Test {
    bytes32 internal constant MARKET = keccak256("fixture market");
    bytes32 internal constant STREAM = keccak256("fixture stream");
    MarketHarness internal markets;

    function setUp() public {
        markets = new MarketHarness();
        markets.configureMarket(MARKET, STREAM, _risk());
        markets.publishTerms(MARKET, _terms());
        markets.setGlobalOiCap(10_000_000e18);
    }

    function test_PublishingTermsPreservesExistingVersion() public {
        LibMarkets.Terms memory next = _terms();
        next.curve.alternate = true;
        next.fees.winProtocolBps = 60;
        assertEq(markets.publishTerms(MARKET, next), 2);
        assertFalse(markets.economicTerms(MARKET, 1).curve.alternate);
        assertEq(markets.economicTerms(MARKET, 1).fees.winProtocolBps, 70);
        assertTrue(markets.economicTerms(MARKET, 2).curve.alternate);
        vm.expectRevert(LibMarkets.TermsChanged.selector);
        markets.admit(MARKET, 1, 100e18, 100, true);
    }

    function test_LoweredCapsPreserveExposureAndBlockNewRisk() public {
        markets.admit(MARKET, 1, 100e18, 100, true);
        LibMarkets.Risk memory r = _risk();
        r.maxLongOiWad = 1;
        markets.configureMarket(MARKET, STREAM, r);
        assertEq(markets.marketState(MARKET).longOiWad, 10_000e18);
        vm.expectRevert(LibMarkets.AdmissionLimit.selector);
        markets.admit(MARKET, 1, 100e18, 100, true);
        markets.admit(MARKET, 1, 100e18, 100, false);
        markets.setGlobalOiCap(1);
        vm.expectRevert(LibMarkets.AdmissionLimit.selector);
        markets.admit(MARKET, 1, 100e18, 100, false);
    }

    function test_InvalidAuthorityConfigurationAndArithmeticAreRejected() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        markets.setGlobalOiCap(1);
        LibMarkets.Terms memory terms = _terms();
        terms.fees.winStakerBps = 10_000;
        vm.expectRevert(LibMarkets.InvalidFeeTerms.selector);
        markets.publishTerms(MARKET, terms);
        terms = _terms();
        terms.fees.keeperLossBps = type(uint16).max;
        markets.publishTerms(MARKET, terms);
    }

    function test_StreamReplacementPreservesExposureAndEconomicVersions() public {
        markets.admit(MARKET, 1, 100e18, 100, true);
        markets.configureMarket(MARKET, bytes32(uint256(1)), _risk());
        assertEq(markets.marketState(MARKET).longOiWad, 10_000e18);
        assertEq(markets.marketState(MARKET).currentTermsVersion, 1);
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        markets.configureMarket(MARKET, STREAM, _risk());
    }

    function test_ZeroSideLimitBlocksOnlyThatSideAndZeroMinimumsAreAllowed() public {
        LibMarkets.Risk memory r = _risk();
        r.maxLongOiWad = 0;
        r.minMarginWad = 0;
        r.minNotionalWad = 0;
        markets.configureMarket(MARKET, STREAM, r);
        vm.expectRevert(LibMarkets.AdmissionLimit.selector);
        markets.admit(MARKET, 1, 0, 100, false);
        vm.expectRevert(LibMarkets.AdmissionLimit.selector);
        markets.admit(MARKET, 1, 100e18, 100, true);
        markets.admit(MARKET, 1, 100e18, 100, false);
    }

    function test_RiskSettingsAreStoredWithoutAdministrativeValidation() public {
        LibMarkets.Risk memory r = _risk();
        r.maxLeverage = 0;
        r.maxMarginWad = 0;
        r.maxNotionalWad = 0;
        r.maxLongOiWad = 0;
        r.maxShortOiWad = 0;
        r.maxTotalOiWad = 0;
        markets.configureMarket(MARKET, STREAM, r);
        vm.expectRevert(LibMarkets.AdmissionLimit.selector);
        markets.admit(MARKET, 1, 100e18, 100, true);
        r = _risk();
        r.maxNotionalWad = type(uint256).max;
        markets.configureMarket(MARKET, STREAM, r);
        markets.admit(MARKET, 1, 100e18, 100, true);
    }

    function test_DisablingOpensPreservesTermsAndBothSides() public {
        markets.admit(MARKET, 1, 100e18, 100, false);
        LibMarkets.Risk memory r = _risk();
        r.opensEnabled = false;
        markets.configureMarket(MARKET, STREAM, r);
        vm.expectRevert(LibMarkets.MarketClosed.selector);
        markets.admit(MARKET, 1, 100e18, 100, true);
        assertEq(markets.marketState(MARKET).shortOiWad, 10_000e18);
        assertEq(markets.marketState(MARKET).currentTermsVersion, 1);
    }

    function _risk() internal pure returns (LibMarkets.Risk memory) {
        // Development fixture. No production calibration is implied.
        return LibMarkets.Risk(
            true, true, 100, 1e18, 100_000e18, 1e18, 1_000_000e18, 5_000_000e18, 5_000_000e18, 10_000_000e18
        );
    }

    function _terms() internal pure returns (LibMarkets.Terms memory) {
        return LibMarkets.Terms(
            LibMarkets.FeeTerms(100, 70, 20, 100, 80, 20, 40, 1e18),
            LibPnl.Curve(0.02e18, 2e18, 1e18, 5e23, false),
            5e14
        );
    }
}
