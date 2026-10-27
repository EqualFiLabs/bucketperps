// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { AccountsInit } from "../../src/init/AccountsInit.sol";
import { AccountFacet } from "../../src/facets/AccountFacet.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";

contract ActivityHarness {
    function setAccount(uint256 id, LibAccountsStorage.Account calldata value) external {
        LibGuard.enter();
        LibAccounts.requireOwner(id);
        // Never allow the fixture to overwrite the synchronization marker.
        bool active = LibAccountsStorage.state().accounts[id].externalStateActive;
        LibAccountsStorage.state().accounts[id] = value;
        LibAccountsStorage.state().accounts[id].externalStateActive = active;
        LibAccounts.syncActivity(id);
        LibGuard.exit();
    }
}

contract AccountLifecycleTest is Test {
    StaticsAccountMock internal statics;
    AccountFacet internal accounts;
    ActivityHarness internal harness;
    address internal alice;
    address internal bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        statics = new StaticsAccountMock();
        statics.mint(alice, 1);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](2);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = AccountFacet.accountState.selector;
        selectors[1] = AccountFacet.hasUnresolvedAccountState.selector;
        selectors[2] = AccountFacet.syncAccountActivity.selector;
        cuts[0] = IDiamondCut.FacetCut(address(new AccountFacet()), IDiamondCut.FacetCutAction.Add, selectors);
        selectors = new bytes4[](1);
        selectors[0] = ActivityHarness.setAccount.selector;
        cuts[1] =
            IDiamondCut.FacetCut(address(new ActivityHarness()), IDiamondCut.FacetCutAction.Add, selectors);
        BucketPerpsDiamond diamond = new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap({
                governor: address(this),
                guardian: bob,
                upgradeDelay: 1 days,
                cuts: cuts,
                init: address(new AccountsInit()),
                data: abi.encodeCall(AccountsInit.initialize, (address(statics), address(statics)))
            })
        );
        accounts = AccountFacet(address(diamond));
        harness = ActivityHarness(address(diamond));
        statics.configure(address(diamond), true);
    }

    function test_ActivityIsIdempotentAndEmptyStateDetaches() public {
        LibAccountsStorage.Account memory a;
        a.cashWad = 10;
        _set(a);
        assertEq(statics.activeLegCount(1), 1);
        accounts.syncAccountActivity(1);
        accounts.syncAccountActivity(1);
        assertEq(statics.activeLegCount(1), 1);
        a.cashWad = 0;
        a.revenueIndexPaid = 123;
        _set(a);
        assertEq(statics.activeLegCount(1), 0);
        assertFalse(accounts.hasUnresolvedAccountState(1));
        assertFalse(accounts.accountState(1).externalStateActive);
        vm.prank(alice);
        statics.close(1);
        vm.expectRevert();
        statics.ownerOf(1);
    }

    function test_OccupiedSyncCannotRemoveLeg() public {
        LibAccountsStorage.Account memory a;
        a.unstakedRewardUnits = 7;
        _set(a);
        vm.prank(bob);
        accounts.syncAccountActivity(1);
        assertEq(statics.activeLegCount(1), 1);
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
    }

    function test_BridgeFailureRollsBackFinancialState() public {
        statics.setFailure(true, address(0), "");
        LibAccountsStorage.Account memory a;
        a.cashWad = 99;
        vm.prank(alice);
        vm.expectRevert();
        harness.setAccount(1, a);
        assertEq(accounts.accountState(1).cashWad, 0);
        assertFalse(accounts.accountState(1).externalStateActive);
        assertEq(statics.activeLegCount(1), 0);
    }

    function testFuzz_EachUnresolvedCategoryBlocksClosure(uint8 category, uint128 amount) public {
        category = uint8(bound(category, 0, 7));
        uint256 value = bound(amount, 1, type(uint128).max);
        LibAccountsStorage.Account memory a;
        if (category == 0) a.cashWad = value;
        else if (category == 1) a.committedClaimMarginWad = value;
        else if (category == 2) a.unstakedRewardUnits = value;
        else if (category == 3) a.rawStakeUnits = value;
        else if (category == 4) a.effectiveWeight = value;
        else if (category == 5) a.claimableRevenueWad = value;
        else if (category == 6) a.openTradeCount = value;
        else a.liveClaimCount = value;
        _set(a);
        assertTrue(accounts.hasUnresolvedAccountState(1));
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
        assertEq(statics.ownerOf(1), alice);
    }

    function test_DisablingModulePreservesProtectionAndAllowsCleanup() public {
        LibAccountsStorage.Account memory a;
        a.liveClaimCount = 1;
        _set(a);
        statics.configure(address(accounts), false);
        accounts.syncAccountActivity(1);
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
        a.liveClaimCount = 0;
        _set(a);
        assertEq(statics.activeLegCount(1), 0);
        a.cashWad = 1;
        vm.prank(alice);
        vm.expectRevert();
        harness.setAccount(1, a);
        assertEq(accounts.accountState(1).cashWad, 0);
    }

    function test_RewardOnlyAccountTransfersAndLinkedLockIsPreserved() public {
        LibAccountsStorage.Account memory a;
        a.unstakedRewardUnits = 17;
        a.rawStakeUnits = 3;
        a.effectiveWeight = 3;
        a.claimableRevenueWad = 5;
        _set(a);
        statics.setGuards(1, false, true, false, false);
        vm.prank(alice);
        vm.expectRevert();
        statics.transferFrom(alice, bob, 1);
        statics.setGuards(1, false, false, false, false);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        harness.setAccount(1, a);
        assertEq(accounts.accountState(1).unstakedRewardUnits, 17);
        assertEq(accounts.accountState(1).claimableRevenueWad, 5);
        assertEq(statics.activeLegCount(1), 1);
        vm.prank(bob);
        harness.setAccount(1, a);
    }

    function test_OtherModuleNamespaceAndExistingObligationsRemain() public {
        address other = makeAddr("other module");
        statics.configure(other, true);
        vm.prank(other);
        statics.attachExternalAccountLeg(1, keccak256("bucketperps.account.v1"), bytes32(uint256(1)));
        LibAccountsStorage.Account memory a;
        a.cashWad = 1;
        _set(a);
        assertEq(statics.activeLegCount(1), 2);
        a.cashWad = 0;
        _set(a);
        assertEq(statics.activeLegCount(1), 1);
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
        vm.prank(other);
        statics.detachExternalAccountLeg(1, keccak256("bucketperps.account.v1"), bytes32(uint256(1)));
        statics.setGuards(1, false, false, true, false);
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
        statics.setGuards(1, false, false, false, true);
        vm.prank(alice);
        vm.expectRevert();
        statics.close(1);
    }

    function test_DetachFailureAndReentrantBridgeAreAtomic() public {
        LibAccountsStorage.Account memory a;
        a.cashWad = 19;
        _set(a);
        statics.setFailure(true, address(0), "");
        a.cashWad = 0;
        vm.prank(alice);
        vm.expectRevert();
        harness.setAccount(1, a);
        assertEq(accounts.accountState(1).cashWad, 19);
        assertTrue(accounts.accountState(1).externalStateActive);
        assertEq(statics.activeLegCount(1), 1);
        statics.setFailure(false, address(accounts), abi.encodeCall(AccountFacet.syncAccountActivity, (1)));
        vm.prank(alice);
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        harness.setAccount(1, a);
        assertEq(accounts.accountState(1).cashWad, 19);
        assertEq(statics.activeLegCount(1), 1);
    }

    function test_InitializingAndMissingPositionsCannotAttach() public {
        LibAccountsStorage.Account memory a;
        a.cashWad = 1;
        statics.setGuards(1, true, false, false, false);
        vm.prank(alice);
        vm.expectRevert();
        harness.setAccount(1, a);
        assertEq(statics.activeLegCount(1), 0);
        vm.expectRevert();
        accounts.syncAccountActivity(999);
    }

    function test_AccountDependencyCannotBeReinitializedThroughNewInitializer() public {
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        AccountsInit another = new AccountsInit();
        bytes memory data = abi.encodeCall(AccountsInit.initialize, (address(statics), address(statics)));
        BucketPerpsDiamond diamond = BucketPerpsDiamond(payable(address(accounts)));
        diamond.scheduleDiamondCut(empty, address(another), data);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(AccountsInit.InvalidInitialization.selector);
        diamond.diamondCut(empty, address(another), data);
    }

    function _set(LibAccountsStorage.Account memory a) internal {
        vm.prank(alice);
        harness.setAccount(1, a);
    }
}
