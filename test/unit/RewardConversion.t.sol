// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { RewardInventoryTest, InventoryHarness } from "./RewardInventory.t.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibRewards } from "../../src/libraries/LibRewards.sol";
import { RewardFacet } from "../../src/facets/RewardFacet.sol";
import { BucketRewardToken } from "../../src/rewards/BucketRewardToken.sol";

contract ConversionHarness is InventoryHarness {
    constructor(address token, address nft) InventoryHarness(token) {
        LibAccountsStorage.state().positionNFT = nft;
        LibAccountsStorage.state().staticsDiamond = nft;
    }

    // Test configuration only. Production conversion controls are a separate governed component.
    function flags(bool wrapping, bool unwrapping) external {
        LibRewards.state().wrappingEnabled = wrapping;
        LibRewards.state().unwrappingEnabled = unwrapping;
    }

    function capacity(uint256 units) external {
        LibRewards.state().wrapCapacityUnits = units;
    }
}

contract RewardConversionTest is RewardInventoryTest {
    ConversionHarness internal c;
    StaticsAccountMock internal nft;

    function setUp() public override {
        super.setUp();
        nft = new StaticsAccountMock();
        nft.mint(address(this), 1);
        c = new ConversionHarness(address(asset), address(nft));
        nft.configure(address(c), true);
        asset.approve(address(c), type(uint256).max);
    }

    function testFuzzBackingAndEntitlementConservation(uint96 funding, uint96 request, uint96 wrapUnits)
        public
    {
        uint256 f = bound(funding, 1, 20e18);
        uint256 w = bound(wrapUnits, 2, 20e18);
        c.fundRewardInventory(f);
        uint256 issued = c.issue(1, request);
        c.capacity(w);
        c.flags(true, true);
        c.wrap(1, w);
        uint256 total = issued + w;
        c.unwrap(1, total / 2, address(this));
        LibRewards.State memory s = c.rewardState();
        uint256 supply = BucketRewardToken(s.receipt).totalSupply();
        assertEq(supply, c.entitlement(1));
        assertEq(supply, s.allocatedUnits);
        assertEq(asset.balanceOf(s.backingVault), s.allocatedUnits);
        assertEq(asset.balanceOf(address(c)), s.inventoryUnits);
        assertEq(s.inventoryUnits + issued, f);
    }

    function testReleaseFailureRestoresReceiptCapacityAndEntitlement() public {
        c.capacity(20e18);
        c.flags(true, true);
        c.wrap(1, 10e18);
        asset.configure(1, false, address(0), "");
        vm.expectRevert();
        c.unwrap(1, 5e18, address(this));
        assertEq(c.entitlement(1), 10e18);
        assertEq(c.rewardState().allocatedUnits, 10e18);
        assertEq(c.rewardState().wrapCapacityUnits, 10e18);
        assertEq(BucketRewardToken(c.rewardState().receipt).totalSupply(), 10e18);
    }

    function testNewOwnerControlsRewardEntitlementAfterSale() public {
        c.capacity(20e18);
        c.flags(true, true);
        c.wrap(1, 10e18);
        address buyer = makeAddr("buyer");
        nft.transferFrom(address(this), buyer, 1);
        vm.expectRevert();
        c.unwrap(1, 1e18, address(this));
        vm.prank(buyer);
        c.unwrap(1, 10e18, buyer);
        assertEq(asset.balanceOf(buyer), 10e18);
        assertEq(c.entitlement(1), 0);
    }

    function testLaunchConversionsAreOff() public {
        vm.expectRevert(RewardFacet.ConversionDisabled.selector);
        c.wrap(1, 1e18);
        vm.expectRevert(RewardFacet.ConversionDisabled.selector);
        c.unwrap(1, 1e18, address(this));
    }

    function testWrapAndUnwrapExistingStaticsWithoutChangingSupply() public {
        uint256 supply = asset.totalSupply();
        c.capacity(20e18);
        c.flags(true, true);
        c.wrap(1, 12e18);
        assertEq(c.entitlement(1), 12e18);
        assertEq(c.rewardState().wrapCapacityUnits, 8e18);
        c.unwrap(1, 5e18, address(this));
        assertEq(c.rewardState().wrapCapacityUnits, 13e18);
        assertEq(c.entitlement(1), 7e18);
        assertEq(c.rewardState().allocatedUnits, 7e18);
        assertEq(asset.balanceOf(c.rewardState().backingVault), 7e18);
        assertEq(asset.totalSupply(), supply);
    }

    function testLossIssuedUnwrapReplenishesOnlyWithBothFlags() public {
        c.fundRewardInventory(20e18);
        c.issue(1, 20e18);
        c.flags(false, true);
        c.unwrap(1, 5e18, address(this));
        assertEq(c.rewardState().wrapCapacityUnits, 0);
        c.flags(true, true);
        c.unwrap(1, 5e18, address(this));
        assertEq(c.rewardState().wrapCapacityUnits, 5e18);
        c.flags(false, false);
        c.flags(true, true);
        assertEq(c.rewardState().wrapCapacityUnits, 5e18);
    }
}
