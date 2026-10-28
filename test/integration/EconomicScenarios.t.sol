// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { BucketRewardToken } from "../../src/rewards/BucketRewardToken.sol";

contract EconomicScenariosTest is ControlProtocolFixture {
    function testOpposingExposureClaimReuseAndRewardTaperRemainInventoryBounded() public {
        _inventory(100e18);
        rewards.setLossRewardRate(2e18);
        uint256 long = _openCash(1, alice, true);
        uint256 short = _openCash(2, bob, false);
        _price(49_900e18);
        vm.prank(bob);
        settlement.closePosition(2, short, block.timestamp, new bytes[](0));
        vm.prank(alice);
        settlement.closePosition(1, long, block.timestamp, new bytes[](0));
        assertEq(accounts.accountState(1).unstakedRewardUnits, 40e18);
        (, uint256 tail, uint256 debt) = queue.queueState();
        assertGt(debt, 0);
        // A queued winner can reuse its claim; no physical cash is created at opening.
        // Use a complete-sized entitlement from the same account when the ordinary winner is smaller.
        uint256 claim = bookView.seedEntitlement(2, 100e18);
        uint256 beforeT = bookView.book().custodyWad;
        _price(50_000e18);
        uint256 claimTrade = _openClaim(2, bob, claim);
        assertEq(bookView.book().custodyWad, beforeT);
        assertGt(tail, 0);
        rewards.setLossRewardRate(1e18);
        _price(1e18);
        liquidation.liquidate(2, claimTrade, new bytes[](0));
        assertEq(accounts.accountState(2).unstakedRewardUnits, 60e18);
        assertEq(rewards.rewardState().inventoryUnits, 0);
        assertEq(rewards.rewardState().allocatedUnits, 100e18);
        assertEq(BucketRewardToken(rewards.rewardState().receipt).totalSupply(), 100e18);
        assertEq(staticsToken.balanceOf(rewards.rewardState().backingVault), 100e18);
        assertFalse(rewards.rewardState().wrappingEnabled);
        assertFalse(rewards.rewardState().unwrappingEnabled);
        // The synthetic book does not account for an off-protocol hedge or its costs.
        assertEq(token.balanceOf(address(diamond)) * 1e12, bookView.book().custodyWad);
    }

    function testNftSaleTransfersAccruedRevenueButCannotCaptureZeroWeightHistory() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        _earnReceipts(2, bob);
        uint256 oldRevenue = staking.pendingStakerRevenue(1);
        vm.prank(alice);
        staking.unstake(1, 20e18);
        _price(50_000e18);
        uint256 id = _openCash(2, bob, true);
        _price(49_900e18);
        vm.prank(bob);
        settlement.closePosition(2, id, block.timestamp, new bytes[](0));
        assertEq(staking.pendingStakerRevenue(1), oldRevenue);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        vm.prank(bob);
        staking.stake(1, 20e18);
        assertEq(staking.pendingStakerRevenue(1), oldRevenue);
        vm.prank(bob);
        staking.claimStakerRevenue(1);
        assertEq(staking.pendingStakerRevenue(1), 0);
    }
}
