// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { CashHarness } from "./Cash.t.sol";
import { MarketFacet } from "../../src/facets/MarketFacet.sol";
import { TradingFacet } from "../../src/facets/TradingFacet.sol";
import { OpenParams, ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";
import { LibOracle } from "../../src/libraries/LibOracle.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";
import { ExecutionOracleMock } from "../mocks/ExecutionOracleMock.sol";

contract CashTradingHarness is CashHarness, MarketFacet, TradingFacet {
    constructor(address nft, address token, address oracle) CashHarness(nft, token) {
        LibProtocol.initialize(msg.sender, msg.sender, 1 days);
        LibOracle.state().executionOracle = oracle;
    }

    /// @dev Fixture-only flat completion to test once-only OI release before settlement exists.
    function retireFlat(uint256 positionId, uint256 id) external {
        LibGuard.enter();
        LibAccounts.requireOwner(positionId);
        LibTrades.Trade storage t = LibTrades.requireLive(positionId, id);
        LibTrades.retire(t);
        LibBookStorage.state().lockedCashMarginWad -= t.marginWad;
        LibBookStorage.state().accountCashWad += t.marginWad;
        LibAccountsStorage.state().accounts[positionId].cashWad += t.marginWad;
        LibAccounts.syncActivity(positionId);
        LibGuard.exit();
    }
}

abstract contract CashTradingFixture is Test {
    bytes32 internal constant MARKET = keccak256("fixture market");
    bytes32 internal constant STREAM = keccak256("fixture stream");
    CashTokenMock internal token;
    StaticsAccountMock internal statics;
    ExecutionOracleMock internal oracle;
    CashTradingHarness internal trading;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new CashTokenMock(6);
        statics = new StaticsAccountMock();
        oracle = new ExecutionOracleMock();
        statics.mint(alice, 1);
        trading = new CashTradingHarness(address(statics), address(token), address(oracle));
        statics.configure(address(trading), true);
        trading.configureMarket(MARKET, STREAM, _risk());
        trading.publishTerms(MARKET, _terms());
        trading.setGlobalOiCap(10_000_000e18);
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(50_000e18, 100, 99, 101, STREAM));
        token.mint(alice, 1_000e6);
        vm.startPrank(alice);
        token.approve(address(trading), type(uint256).max);
        trading.deposit(1, 1_000e6);
        vm.stopPrank();
    }

    function _params(bool isLong) internal view returns (OpenParams memory) {
        return OpenParams(MARKET, isLong, FundingSource.Cash, 100e18, 100, 1, block.timestamp);
    }

    function _risk() internal pure returns (LibMarkets.Risk memory) {
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

contract CashTradingTest is CashTradingFixture {
    function test_CashOpenReclassifiesPrincipalWithoutHouseCapital() public {
        vm.prank(alice);
        uint256 id = trading.openPosition(1, _params(true), new ClaimPortion[](0), new bytes[](0));
        LibTrades.Trade memory t = trading.tradeState(id);
        assertEq(trading.book().custodyWad, 1_000e18);
        assertEq(trading.book().accountCashWad, 900e18);
        assertEq(trading.book().lockedCashMarginWad, 100e18);
        assertEq(trading.book().fundedPayablesWad, 0);
        assertEq(trading.book().realizedHousePnlWad, 0);
        assertEq(trading.marketState(MARKET).longOiWad, 10_000e18);
        assertEq(trading.marketState(MARKET).shortOiWad, 0);
        assertEq(trading.accountState(1).openTradeCount, 1);
        assertEq(t.positionId, 1);
        assertEq(t.entryPrice1e18, 50_000e18);
        assertLt(t.bustPrice1e18, t.entryPrice1e18);
        assertEq(t.termsVersion, 1);
        assertEq(statics.activeLegCount(1), 1);
        vm.prank(alice);
        vm.expectRevert();
        trading.withdraw(1, 1_000e18, alice);
        vm.prank(alice);
        trading.withdraw(1, 900e18, alice);
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
    }

    function testFuzz_OpeningConservesCashAndMatchesDirectionalExposure(
        uint64 marginSeed,
        uint8 leverageSeed,
        bool isLong
    ) public {
        OpenParams memory p = _params(isLong);
        p.marginWad = bound(marginSeed, 1e6, 1_000e6) * 1e12;
        p.leverage = uint32(bound(leverageSeed, 2, 100));
        vm.prank(alice);
        uint256 id = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        assertEq(
            trading.book().accountCashWad + trading.book().lockedCashMarginWad, trading.book().custodyWad
        );
        assertEq(trading.book().lockedCashMarginWad, p.marginWad);
        (uint256 oi,) = trading.globalOpenInterest();
        assertEq(oi, p.marginWad * p.leverage);
        assertEq(trading.tradeState(id).notionalWad, oi);
        assertEq(trading.marketState(MARKET).longOiWad, isLong ? oi : 0);
        assertEq(trading.marketState(MARKET).shortOiWad, isLong ? 0 : oi);
        assertEq(trading.accountState(1).openTradeCount, 1);
    }

    function test_ShortOpenAndTransferredFinancialAuthority() public {
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        trading.openPosition(1, _params(false), new ClaimPortion[](0), new bytes[](0));
        vm.prank(bob);
        uint256 id = trading.openPosition(1, _params(false), new ClaimPortion[](0), new bytes[](0));
        assertGt(trading.tradeState(id).bustPrice1e18, 50_000e18);
        assertEq(trading.marketState(MARKET).shortOiWad, 10_000e18);
        assertEq(trading.accountState(1).cashWad, 900e18);
    }

    function test_DeadlineVersionFundingAndLimitsFailWithoutChangingBook() public {
        OpenParams memory p = _params(true);
        p.deadline = block.timestamp - 1;
        vm.prank(alice);
        vm.expectRevert(LibTrades.DeadlineExpired.selector);
        trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        p = _params(true);
        p.expectedTermsVersion = 2;
        vm.prank(alice);
        vm.expectRevert(LibMarkets.TermsChanged.selector);
        trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        p = _params(true);
        p.fundingSource = FundingSource.Claim;
        vm.prank(alice);
        vm.expectRevert(LibTrades.InvalidFunding.selector);
        trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        p = _params(true);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(1, 1e18);
        vm.prank(alice);
        vm.expectRevert(LibTrades.InvalidFunding.selector);
        trading.openPosition(1, p, portions, new bytes[](0));
        p.leverage = 101;
        vm.prank(alice);
        vm.expectRevert(LibMarkets.AdmissionLimit.selector);
        trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        assertEq(trading.book().lockedCashMarginWad, 0);
        assertEq(trading.accountState(1).cashWad, 1_000e18);
        (uint256 oi,) = trading.globalOpenInterest();
        assertEq(oi, 0);
    }

    function test_OracleFailureRollsBackAndEntrySideBustThresholdIsAccepted() public {
        oracle.setFailure(hex"deadbeef");
        vm.prank(alice);
        vm.expectRevert(bytes4(0xdeadbeef));
        trading.openPosition(1, _params(true), new ClaimPortion[](0), new bytes[](0));
        assertEq(trading.accountState(1).cashWad, 1_000e18);
        assertEq(trading.book().lockedCashMarginWad, 0);
        assertEq(trading.marketState(MARKET).longOiWad, 0);
        oracle.setFailure("");
        LibMarkets.Terms memory terms = _terms();
        terms.liquidationBufferWad = 0.5e18;
        trading.publishTerms(MARKET, terms);
        OpenParams memory p = _params(true);
        p.expectedTermsVersion = 2;
        vm.prank(alice);
        uint256 id = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        assertEq(trading.tradeState(id).bustPrice1e18, 74_250e18);
        assertEq(trading.accountState(1).cashWad, 900e18);
        assertEq(trading.marketState(MARKET).longOiWad, 10_000e18);
    }

    function test_OneTimesLongAcceptsRecoveredZeroBustThreshold() public {
        OpenParams memory p = _params(true);
        p.leverage = 1;
        vm.prank(alice);
        uint256 id = trading.openPosition(1, p, new ClaimPortion[](0), new bytes[](0));
        assertEq(trading.tradeState(id).bustPrice1e18, 0);
        assertEq(trading.book().lockedCashMarginWad, 100e18);
    }
}
