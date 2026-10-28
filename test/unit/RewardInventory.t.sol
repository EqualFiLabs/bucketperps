// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { RewardFacet } from "../../src/facets/RewardFacet.sol";
import { RewardsInit } from "../../src/init/RewardsInit.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";
import { LibRewards } from "../../src/libraries/LibRewards.sol";
import { BackingVault } from "../../src/rewards/BackingVault.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";

contract InventoryHarness is RewardFacet {
    constructor(address token) {
        LibProtocol.state().initializing = true;
        (bool ok,) = address(new RewardsInit()).delegatecall(abi.encodeCall(RewardsInit.initialize, (token)));
        require(ok);
        LibProtocol.state().initializing = false;
    }
}

contract RewardInventoryTest is Test {
    CashTokenMock internal asset;
    InventoryHarness internal h;

    function setUp() public {
        asset = new CashTokenMock(18);
        h = new InventoryHarness(address(asset));
        asset.mint(address(this), 100e18);
        asset.approve(address(h), type(uint256).max);
    }

    function testFundingSeparatesUnallocatedCustody() public {
        h.fundRewardInventory(30e18);
        LibRewards.State memory s = h.rewardState();
        assertEq(s.inventoryUnits, 30e18);
        assertEq(s.allocatedUnits, 0);
        assertEq(asset.balanceOf(address(h)), 30e18);
        assertEq(asset.balanceOf(s.backingVault), 0);
        assertFalse(s.wrappingEnabled);
        assertFalse(s.unwrappingEnabled);
        assertEq(s.wrapCapacityUnits, 0);
    }

    function testDonationDoesNotBecomeInventory() public {
        asset.transfer(address(h), 7e18);
        assertEq(h.rewardState().inventoryUnits, 0);
    }

    function testInexactFundingRollsBack() public {
        asset.configure(1, false, address(0), "");
        vm.expectRevert(LibRewards.InexactTransfer.selector);
        h.fundRewardInventory(30e18);
        assertEq(h.rewardState().inventoryUnits, 0);
        assertEq(asset.balanceOf(address(h)), 0);
    }

    function testBackingCannotBeReleasedByFunder() public {
        BackingVault vault = BackingVault(h.rewardState().backingVault);
        vm.expectRevert(BackingVault.Unauthorized.selector);
        vault.release(address(this), 1);
    }
}
