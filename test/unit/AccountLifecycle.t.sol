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

    function _set(LibAccountsStorage.Account memory a) internal {
        vm.prank(alice);
        harness.setAccount(1, a);
    }
}
