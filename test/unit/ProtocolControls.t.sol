// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";
import { LibControls } from "../../src/libraries/LibControls.sol";

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
