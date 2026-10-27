// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { CashTradingFixture, CashTradingHarness } from "./CashTrading.t.sol";
import { QueueFacet } from "../../src/facets/QueueFacet.sol";
import { LibQueue } from "../../src/libraries/LibQueue.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { OpenParams, ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

contract ClaimTradingHarness is CashTradingHarness, QueueFacet {
    /// @dev Fixture representing previously realized cash losses, not donation classification.
    function seedHouse(uint256 cashWad, uint256 sideWad) external {
        LibBookStorage.state().custodyWad += cashWad;
        LibBookStorage.state().realizedHousePnlWad += int256(cashWad);
        LibBookStorage.state().sideBucketWad += sideWad;
    }

    constructor(address nft, address token, address oracle) CashTradingHarness(nft, token, oracle) { }

    function seedEntitlement(uint256 positionId, uint256 amount) external returns (uint256 id) {
        LibGuard.enter();
        LibBookStorage.state().realizedHousePnlWad -= int256(amount);
        id = LibQueue.enqueue(positionId, amount);
        LibGuard.exit();
    }
}

abstract contract ClaimFundingFixture is CashTradingFixture {
    ClaimTradingHarness internal claims;

    function setUp() public virtual override {
        super.setUp();
        claims = ClaimTradingHarness(address(trading));
    }

    function _deployTrading() internal override returns (CashTradingHarness) {
        return new ClaimTradingHarness(address(statics), address(token), address(oracle));
    }

    function _claimParams() internal view returns (OpenParams memory p) {
        p = _params(true);
        p.fundingSource = FundingSource.Claim;
    }
}

contract ClaimFundingTest is ClaimFundingFixture {
    function test_PartialConsumptionMovesOnlyDebtAndPreservesRemainingPriority() public {
        uint256 first = claims.seedEntitlement(1, 150e18);
        uint256 later = claims.seedEntitlement(1, 40e18);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(first, 100e18);
        int256 beforeP = trading.book().realizedHousePnlWad;
        vm.prank(alice);
        uint256 tradeId = trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(trading.book().custodyWad, 1_000e18);
        assertEq(trading.book().accountCashWad, 1_000e18);
        assertEq(trading.book().lockedCashMarginWad, 0);
        assertEq(trading.book().queuedDebtWad, 90e18);
        assertEq(trading.book().committedDebtWad, 100e18);
        assertEq(trading.book().realizedHousePnlWad, beforeP);
        assertEq(claims.claimState(first).remainingWad, 50e18);
        assertEq(claims.claimState(later).remainingWad, 40e18);
        (uint256 head,,) = claims.queueState();
        assertEq(head, first);
        assertEq(trading.accountState(1).liveClaimCount, 2);
        assertEq(trading.accountState(1).committedClaimMarginWad, 100e18);
        assertEq(uint256(trading.tradeState(tradeId).fundingSource), uint256(FundingSource.Claim));
    }

    function test_DuplicateWrongAccountAndOverconsumptionAreAtomic() public {
        uint256 id = claims.seedEntitlement(1, 100e18);
        statics.mint(bob, 2);
        uint256 other = claims.seedEntitlement(2, 100e18);
        ClaimPortion[] memory portions = new ClaimPortion[](2);
        portions[0] = ClaimPortion(id, 50e18);
        portions[1] = ClaimPortion(id, 50e18);
        vm.prank(alice);
        vm.expectRevert(LibQueue.DuplicateClaim.selector);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(claims.claimState(id).remainingWad, 100e18);
        portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(other, 100e18);
        vm.prank(alice);
        vm.expectRevert(LibQueue.InvalidClaimPortion.selector);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        portions[0] = ClaimPortion(id, 101e18);
        vm.prank(alice);
        vm.expectRevert(LibQueue.InvalidClaimPortion.selector);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        portions[0] = ClaimPortion(id, 99e18);
        vm.prank(alice);
        vm.expectRevert(LibQueue.InvalidClaimAmount.selector);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(trading.book().committedDebtWad, 0);
        assertEq(trading.book().queuedDebtWad, 200e18);
    }

    function test_LastEntryConsumptionCreatesNoCashAndKeepsAccountActive() public {
        uint256 id = claims.seedEntitlement(1, 100e18);
        vm.prank(alice);
        trading.withdraw(1, 1_000e18, alice);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(id, 100e18);
        vm.prank(alice);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(trading.book().queuedDebtWad, 0);
        assertEq(trading.book().committedDebtWad, 100e18);
        assertEq(trading.book().custodyWad, 0);
        assertEq(trading.book().fundedPayablesWad, 0);
        assertEq(trading.accountState(1).liveClaimCount, 0);
        assertTrue(trading.accountState(1).externalStateActive);
        assertEq(statics.activeLegCount(1), 1);
    }

    function test_OracleFailureRestoresConsumedPriorityAndDebt() public {
        uint256 id = claims.seedEntitlement(1, 100e18);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(id, 100e18);
        oracle.setFailure(hex"deadbeef");
        vm.prank(alice);
        vm.expectRevert(bytes4(0xdeadbeef));
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(claims.claimState(id).remainingWad, 100e18);
        assertEq(trading.accountState(1).liveClaimCount, 1);
        assertEq(trading.book().committedDebtWad, 0);
        (uint256 head,,) = claims.queueState();
        assertEq(head, id);
    }
}
