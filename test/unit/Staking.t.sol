// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StakingProtocolFixture } from "../helpers/StakingProtocolFixture.sol";

contract StakingTest is StakingProtocolFixture {
    function testStakeAccruesOnlyFutureFundedFeesAndClaimReclassifiesCash() public {
        _earnReceipts(1, alice);
        assertEq(staking.pendingStakerRevenue(1), 0);
        vm.prank(alice);
        staking.stake(1, 20e18);
        _earnReceipts(2, bob);
        assertEq(staking.pendingStakerRevenue(1), 0.2e18);
        uint256 beforeF = bookView.book().fundedPayablesWad;
        uint256 beforeC = accounts.accountState(1).cashWad;
        uint256 beforeT = bookView.book().custodyWad;
        vm.prank(alice);
        assertEq(staking.claimStakerRevenue(1), 0.2e18);
        assertEq(bookView.book().fundedPayablesWad, beforeF - 0.2e18);
        assertEq(accounts.accountState(1).cashWad, beforeC + 0.2e18);
        assertEq(bookView.book().custodyWad, beforeT);
    }

    function testUnstakeDoesNotReleaseBackingAndBuyerOwnsRevenue() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        _earnReceipts(2, bob);
        uint256 backing = staticsToken.balanceOf(rewards.rewardState().backingVault);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert();
        staking.claimStakerRevenue(1);
        vm.prank(bob);
        staking.unstake(1, 20e18);
        assertEq(staticsToken.balanceOf(rewards.rewardState().backingVault), backing);
        assertEq(accounts.accountState(1).unstakedRewardUnits, 20e18);
        vm.prank(bob);
        assertEq(staking.claimStakerRevenue(1), 0.2e18);
    }
}
