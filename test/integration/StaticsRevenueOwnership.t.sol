// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StakingProtocolFixture } from "../helpers/StakingProtocolFixture.sol";

/// @dev Proposed bridge fixture coverage; real Statics notification coverage remains unqualified.
contract StaticsRevenueOwnershipTest is StakingProtocolFixture {
    function testUnlinkSaleRelinkChangesOnlyFutureRevenue() public {
        _earnReceipts(1, alice);
        _earnReceipts(2, bob);
        statics.changeMultiplier(address(diamond), 1, 20_000);
        vm.prank(alice);
        staking.stake(1, 20e18);
        vm.prank(bob);
        staking.stake(2, 20e18);
        statics.setGuards(1, false, true, false, false);
        vm.prank(alice);
        vm.expectRevert();
        statics.transferFrom(alice, bob, 1);
        _loss();
        uint256 past = staking.pendingStakerRevenue(1);
        assertEq(past, 133_333_000_000_000_000);
        statics.changeMultiplier(address(diamond), 1, 10_000);
        statics.setGuards(1, false, false, false, false);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        assertEq(staking.pendingStakerRevenue(1), past);
        assertEq(accounts.accountState(1).effectiveWeight, 20e18);
        statics.changeMultiplier(address(diamond), 1, 30_000);
        _loss();
        assertEq(staking.pendingStakerRevenue(1), past + 0.15e18);
        assertEq(accounts.accountState(1).rawStakeUnits, 20e18);
        vm.prank(alice);
        vm.expectRevert();
        staking.unstake(1, 1);
        vm.prank(bob);
        staking.claimStakerRevenue(1);
        assertGt(accounts.accountState(1).cashWad, 900e18);
    }

    function _loss() internal {
        _price(50_000e18);
        uint256 id = _openCash(2, bob, true);
        _price(49_900e18);
        vm.prank(bob);
        settlement.closePosition(2, id, block.timestamp, new bytes[](0));
    }
}
