// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StakingProtocolFixture } from "../helpers/StakingProtocolFixture.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";

contract StaticsWeightCheckpointTest is StakingProtocolFixture {
    function testReentrantNotificationRollsBackCanonicalAndLocalState() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        staticsToken.mint(address(this), 1e18);
        staticsToken.approve(address(diamond), 1e18);
        staticsToken.configure(
            0,
            false,
            address(statics),
            abi.encodeCall(StaticsAccountMock.changeMultiplier, (address(diamond), 1, 20_000))
        );
        vm.expectRevert();
        rewards.fundRewardInventory(1e18);
        assertEq(statics.accountMultiplierBps(1), 10_000);
        assertEq(accounts.accountState(1).effectiveWeight, 20e18);
        (uint256 raw, uint256 weight,,) = staking.stakingTotals();
        assertEq(raw, 20e18);
        assertEq(weight, 20e18);
    }

    function testRejectedCanonicalTransitionIsAtomic() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        // A mismatched local checkpoint simulates a missing prior notification.
        vm.prank(address(statics));
        staking.onAccountMultiplierChanged(1, 10_000, 15_000);
        vm.expectRevert(StakingFacet.InvalidWeightCallback.selector);
        statics.changeMultiplier(address(diamond), 1, 20_000);
        assertEq(statics.accountMultiplierBps(1), 10_000);
        assertEq(accounts.accountState(1).effectiveWeight, 30e18);
    }

    function testRepeatedCanonicalTransitionsPreserveRawStakeAndGlobalSum() public {
        _earnReceipts(1, alice);
        _earnReceipts(2, bob);
        vm.prank(alice);
        staking.stake(1, 20e18);
        vm.prank(bob);
        staking.stake(2, 20e18);
        uint256[5] memory phases = [uint256(20_000), 30_000, 10_000, 15_000, 10_000];
        for (uint256 i; i < phases.length; ++i) {
            statics.changeMultiplier(address(diamond), 1, phases[i]);
            (, uint256 total,,) = staking.stakingTotals();
            assertEq(
                total, accounts.accountState(1).effectiveWeight + accounts.accountState(2).effectiveWeight
            );
            assertEq(accounts.accountState(1).rawStakeUnits, 20e18);
        }
    }
}
