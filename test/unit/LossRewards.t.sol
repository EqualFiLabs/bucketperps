// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { RewardProtocolFixture } from "../helpers/RewardProtocolFixture.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";

contract LossRewardsTest is RewardProtocolFixture {
    function testRateIsImmediateConfigurableAndDoesNotIssue() public {
        rewards.setLossRewardRate(5e18);
        assertEq(rewards.rewardState().rewardUnitsPerDollar, 5e18);
        rewards.setLossRewardRate(1e18);
        assertEq(rewards.rewardState().rewardUnitsPerDollar, 1e18);
        assertEq(accounts.accountState(1).unstakedRewardUnits, 0);
        vm.prank(alice);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        rewards.setLossRewardRate(10e18);
    }
}
