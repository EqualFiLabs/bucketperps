// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ClaimFundingFixture } from "./ClaimFunding.t.sol";
import { LibQueue } from "../../src/libraries/LibQueue.sol";

contract HarvestTest is ClaimFundingFixture {
    function test_PartialHeadThenNextEntryAndSideBucketFirst() public {
        statics.mint(bob, 2);
        uint256 first = claims.seedEntitlement(1, 100e18);
        uint256 next = claims.seedEntitlement(2, 40e18);
        _fundHouse(60e18, 50e18);
        int256 beforeP = trading.book().realizedHousePnlWad;
        vm.prank(makeAddr("keeper"));
        assertEq(claims.harvest(128), 60e18);
        assertEq(claims.claimState(first).remainingWad, 40e18);
        assertEq(claims.claimState(next).remainingWad, 40e18);
        assertEq(trading.accountState(1).cashWad, 1_060e18);
        assertEq(trading.accountState(2).cashWad, 0);
        assertEq(trading.book().sideBucketWad, 0);
        assertEq(trading.book().realizedHousePnlWad, beforeP);
        _fundHouse(100e18, 80e18);
        beforeP = trading.book().realizedHousePnlWad;
        assertEq(claims.harvest(1), 40e18);
        assertEq(trading.book().sideBucketWad, 40e18);
        assertEq(trading.accountState(2).cashWad, 0);
        assertEq(claims.harvest(1), 40e18);
        assertEq(trading.book().queuedDebtWad, 0);
        assertEq(trading.book().sideBucketWad, 0);
        assertEq(trading.book().realizedHousePnlWad, beforeP);
        assertEq(trading.accountState(2).cashWad, 40e18);
        assertEq(trading.book().custodyWad - trading.book().accountCashWad, 20e18);
    }

    function test_UserCashCannotFundTheQueue() public {
        claims.seedEntitlement(1, 100e18);
        assertEq(claims.harvest(128), 0);
        assertEq(trading.book().queuedDebtWad, 100e18);
        assertEq(trading.book().accountCashWad, 1_000e18);
        assertEq(trading.accountState(1).liveClaimCount, 1);
    }

    function test_NftSalePaysAccountAndFormerOwnerCannotWithdraw() public {
        claims.seedEntitlement(1, 100e18);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        _fundHouse(100e18, 100e18);
        assertEq(claims.harvest(128), 100e18);
        assertEq(trading.accountState(1).cashWad, 1_100e18);
        vm.prank(alice);
        vm.expectRevert();
        trading.withdraw(1, 100e18, alice);
        vm.prank(bob);
        trading.withdraw(1, 100e18, bob);
        assertEq(token.balanceOf(bob), 100e6);
    }

    function test_InvalidWorkBoundsRevertWithoutPayment() public {
        claims.seedEntitlement(1, 100e18);
        _fundHouse(100e18, 0);
        vm.expectRevert(LibQueue.InvalidBound.selector);
        claims.harvest(0);
        vm.expectRevert(LibQueue.InvalidBound.selector);
        claims.harvest(129);
        assertEq(trading.book().queuedDebtWad, 100e18);
        assertEq(trading.accountState(1).cashWad, 1_000e18);
    }

    function _fundHouse(uint256 cashWad, uint256 sideWad) internal {
        token.mint(address(trading), cashWad / 1e12);
        claims.seedHouse(cashWad, sideWad);
    }
}
