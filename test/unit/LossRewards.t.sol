// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { RewardProtocolFixture } from "../helpers/RewardProtocolFixture.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";

contract LossRewardsTest is RewardProtocolFixture {
    function testCashAndClaimLossesUseSameBasisAndStartUnstaked() public {
        _inventory(1000e18);
        rewards.setLossRewardRate(2e18);
        uint256 cashTrade = _openCash(1, alice, true);
        uint256 claim = bookView.seedEntitlement(2, 100e18);
        uint256 claimTrade = _openClaim(2, bob, claim);
        _price(49_900e18);
        vm.prank(alice);
        settlement.closePosition(1, cashTrade, block.timestamp, new bytes[](0));
        vm.prank(bob);
        settlement.closePosition(2, claimTrade, block.timestamp, new bytes[](0));
        assertEq(accounts.accountState(1).unstakedRewardUnits, 40e18);
        assertEq(accounts.accountState(2).unstakedRewardUnits, 40e18);
        assertEq(accounts.accountState(1).rawStakeUnits, 0);
        assertEq(rewards.rewardState().allocatedUnits, 80e18);
    }

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
