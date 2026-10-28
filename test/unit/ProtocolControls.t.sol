// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";
import { LibControls } from "../../src/libraries/LibControls.sol";

import { ExecutionOracleMock } from "../mocks/ExecutionOracleMock.sol";

import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";

contract ProtocolControlsTest is ControlProtocolFixture {
    function testOpensPausePreservesClosesButSettlementPauseBlocksBoth() public {
        uint256 id = _openCash(1, alice, true);
        vm.prank(bob);
        controls.pause(LibControls.OPENS);
        vm.expectRevert();
        _openCash(2, bob, true);
        vm.prank(alice);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        controls.unpause(LibControls.OPENS);
        id = _openCash(1, alice, true);
        controls.pause(LibControls.SETTLEMENT);
        _price(1e18);
        vm.expectRevert();
        liquidation.liquidate(1, id, new bytes[](0));
        vm.prank(alice);
        vm.expectRevert();
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        vm.expectRevert();
        _openCash(2, bob, true);
        vm.prank(alice);
        cash.withdraw(1, 1e18, alice);
    }

    function testRewardPauseSkipsIssuanceWithoutBlockingSettlementOrCallbacks() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        uint256 id = _openCash(1, alice, true);
        controls.pause(LibControls.REWARDS | LibControls.STAKING);
        statics.changeMultiplier(address(diamond), 1, 20_000);
        assertEq(accounts.accountState(1).effectiveWeight, 40e18);
        _price(49_900e18);
        vm.prank(alice);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(accounts.accountState(1).unstakedRewardUnits, 0);
        assertTrue(trading.tradeState(id).settled);
    }

    function testTypedDependencyDelayBindsPayloadAndExecutesOnce() public {
        controls.setSafetyDelays(0, 1 days);
        ExecutionOracleMock replacement = new ExecutionOracleMock();
        bytes32 operation = keccak256(abi.encode("oracle", address(replacement)));
        controls.scheduleSafetyAction(operation);
        vm.expectRevert();
        controls.executeOracle(address(replacement));
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert();
        controls.executeOracle(address(oracle));
        controls.executeOracle(address(replacement));
        vm.expectRevert();
        controls.executeOracle(address(replacement));
        assertEq(controls.safetyAction(operation), 0);
        controls.setSafetyDelays(0, 0);
        controls.scheduleSafetyAction(keccak256(abi.encode("oracle", address(oracle))));
        controls.executeOracle(address(oracle));
        _openCash(1, alice, true);
    }

    function testFinalizationBlocksPendingAndFutureCutsButRetainsOperations() public {
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](0);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.prank(bob);
        vm.expectRevert();
        controls.finalizeProtocol();
        controls.finalizeProtocol();
        (,,, bool finalized) = diamond.protocolState();
        assertTrue(finalized);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert();
        diamond.diamondCut(cuts, address(0), "");
        vm.expectRevert();
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.expectRevert();
        controls.finalizeProtocol();
        controls.setSafetyDelays(0, 0);
        vm.expectRevert();
        diamond.scheduleDiamondCut(cuts, address(0), "");
        rewards.setLossRewardRate(1e18);
        controls.pause(LibControls.OPENS);
        controls.unpause(LibControls.OPENS);
        _house(10e18);
        houseFacet.distributeSurplus(1e18);
        uint256 id = _openCash(1, alice, true);
        vm.prank(alice);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
    }

    function testGuardianCannotUnpauseAndIncidentPauseBlocksExits() public {
        vm.prank(bob);
        controls.pause(type(uint256).max);
        vm.prank(bob);
        vm.expectRevert();
        controls.unpause(type(uint256).max);
        vm.prank(alice);
        vm.expectRevert();
        cash.withdraw(1, 1e18, alice);
        controls.unpause(type(uint256).max);
        vm.prank(alice);
        cash.withdraw(1, 1e18, alice);
    }
}
