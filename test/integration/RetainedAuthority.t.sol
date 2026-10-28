// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { DollarProtocolFixture } from "../helpers/DollarProtocolFixture.sol";
import { BackingVault } from "../../src/rewards/BackingVault.sol";
import { BucketRewardToken } from "../../src/rewards/BucketRewardToken.sol";
import { ExecutionOracleMock } from "../mocks/ExecutionOracleMock.sol";
import { RewardsInit } from "../../src/init/RewardsInit.sol";
import { OperatorRouterInit } from "../../src/init/OperatorRouterInit.sol";

contract RetainedAuthorityTest is DollarProtocolFixture {
    function testNftApprovalNeverGrantsStakeRevenueOrBackingAuthority() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        statics.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert();
        staking.stake(1, 1e18);
        vm.prank(bob);
        vm.expectRevert();
        staking.claimStakerRevenue(1);
        vm.prank(bob);
        vm.expectRevert();
        assetFacet.withdrawUsdG(1, 1e18, bob);
        BackingVault vault = BackingVault(rewards.rewardState().backingVault);
        BucketRewardToken receipt = BucketRewardToken(rewards.rewardState().receipt);
        vm.expectRevert();
        vault.release(alice, 1e18);
        vm.expectRevert();
        receipt.mint(1e18);
        assertEq(accounts.accountState(1).unstakedRewardUnits, 20e18);
        assertEq(staticsToken.balanceOf(address(vault)), 20e18);
    }

    function testUnauthorizedExecutionCannotConsumeScheduledPayloadAfterFinalization() public {
        ExecutionOracleMock replacement = new ExecutionOracleMock();
        bytes32 operation = keccak256(abi.encode("oracle", address(replacement)));
        controls.scheduleSafetyAction(operation);
        controls.finalizeProtocol();
        uint256 ready = controls.safetyAction(operation);
        vm.prank(alice);
        vm.expectRevert();
        controls.executeOracle(address(replacement));
        assertEq(controls.safetyAction(operation), ready);
        controls.executeOracle(address(replacement));
        assertEq(controls.safetyAction(operation), 0);
        vm.prank(bob);
        vm.expectRevert();
        controls.setSafetyDelays(0, 0);
    }

    function testComponentInitializersAreNotCallableOperationalSetters() public {
        RewardsInit rewardInit = new RewardsInit();
        OperatorRouterInit routerInit = new OperatorRouterInit();
        vm.expectRevert();
        rewardInit.initialize(address(staticsToken));
        vm.expectRevert();
        routerInit.initialize(address(dollarCore));
        controls.finalizeProtocol();
        vm.expectRevert();
        rewardInit.initialize(address(staticsToken));
        vm.expectRevert();
        routerInit.initialize(address(dollarCore));
    }
}
