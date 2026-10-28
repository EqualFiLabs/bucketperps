// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";
import { LibControls } from "../../src/libraries/LibControls.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { BucketRewardToken } from "../../src/rewards/BucketRewardToken.sol";

contract RewardsAcceptanceTest is ControlProtocolFixture {
    function testRewardStakeSaleAndIncidentConserveCustodyAfterFinalization() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        statics.changeMultiplier(address(diamond), 1, 20_000);
        _earnReceipts(2, bob);
        statics.changeMultiplier(address(diamond), 1, 10_000);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        controls.finalizeProtocol();
        controls.pause(LibControls.OPENS | LibControls.REWARDS | LibControls.STAKING);
        statics.changeMultiplier(address(diamond), 1, 15_000);
        uint256 beforeT = bookView.book().custodyWad;
        vm.prank(bob);
        staking.claimStakerRevenue(1);
        assertEq(bookView.book().custodyWad, beforeT);
        controls.unpause(LibControls.STAKING);
        vm.prank(bob);
        staking.unstake(1, 20e18);
        uint256 allocated = rewards.rewardState().allocatedUnits;
        assertEq(
            allocated,
            accounts.accountState(1).unstakedRewardUnits + accounts.accountState(2).unstakedRewardUnits
        );
        assertEq(BucketRewardToken(rewards.rewardState().receipt).totalSupply(), allocated);
        assertEq(staticsToken.balanceOf(rewards.rewardState().backingVault), allocated);
        assertEq(staticsToken.balanceOf(address(diamond)), rewards.rewardState().inventoryUnits);
        LibBookStorage.State memory b = bookView.book();
        assertEq(token.balanceOf(address(diamond)) * 1e12, b.custodyWad);
        assertEq(b.accountCashWad, accounts.accountState(1).cashWad + accounts.accountState(2).cashWad);
        assertEq(
            b.fundedPayablesWad,
            feeFacet.feePayables().protocolPayableWad + feeFacet.feePayables().operatorPayableWad
                + feeFacet.feePayables().stakerPayableWad
        );
        assertLe(b.accountCashWad + b.lockedCashMarginWad + b.fundedPayablesWad, b.custodyWad);
    }
}
