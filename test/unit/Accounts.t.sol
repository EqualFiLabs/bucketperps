// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { AccountsInit } from "../../src/init/AccountsInit.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";

/// @dev Minimal ownership fixture. Actual Statics lifecycle qualification is a separate gate.
contract MockPosition {
    mapping(uint256 => address) internal owners;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function ownerOf(uint256 id) public view returns (address who) {
        who = owners[id];
        require(who != address(0), "missing position");
    }

    function mint(address to, uint256 id) external {
        require(to != address(0) && owners[id] == address(0));
        owners[id] = to;
    }

    function approve(address to, uint256 id) external {
        require(msg.sender == ownerOf(id));
        getApproved[id] = to;
    }

    function setApprovalForAll(address to, bool allowed) external {
        isApprovedForAll[msg.sender][to] = allowed;
    }

    function transferFrom(address from, address to, uint256 id) public virtual {
        require(ownerOf(id) == from && to != address(0));
        require(msg.sender == from || getApproved[id] == msg.sender || isApprovedForAll[from][msg.sender]);
        delete getApproved[id];
        owners[id] = to;
    }
}

contract AccountsHarness {
    function authorized(uint256 id) external view returns (bool) {
        LibAccounts.requireOwner(id);
        return true;
    }

    function settings() external view returns (address, address) {
        return (LibAccountsStorage.state().positionNFT, LibAccountsStorage.state().staticsDiamond);
    }
}

contract AccountsTest is Test {
    MockPosition internal nft;
    BucketPerpsDiamond internal diamond;
    AccountsHarness internal account;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        nft = new MockPosition();
        nft.mint(alice, 1);
        AccountsHarness implementation = new AccountsHarness();
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = AccountsHarness.authorized.selector;
        selectors[1] = AccountsHarness.settings.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut(address(implementation), IDiamondCut.FacetCutAction.Add, selectors);
        AccountsInit init = new AccountsInit();
        diamond = new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap({
                governor: address(this),
                guardian: bob,
                upgradeDelay: 1 days,
                cuts: cuts,
                init: address(init),
                data: abi.encodeCall(AccountsInit.initialize, (address(nft), address(nft)))
            })
        );
        account = AccountsHarness(address(diamond));
    }

    function test_CurrentOwnerOnlyAndTransferChangesAuthority() public {
        vm.prank(alice);
        assertTrue(account.authorized(1));
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        account.authorized(1);
        vm.prank(bob);
        assertTrue(account.authorized(1));
    }

    function test_ApprovalsDoNotAuthorizeFinancialActions() public {
        vm.prank(alice);
        nft.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        account.authorized(1);
        vm.prank(alice);
        nft.setApprovalForAll(bob, true);
        vm.prank(bob);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        account.authorized(1);
    }

    function test_NonexistentPositionAndDirectInitializerFail() public {
        vm.expectRevert();
        account.authorized(999);
        AccountsInit init = new AccountsInit();
        vm.expectRevert(AccountsInit.InvalidInitialization.selector);
        init.initialize(address(nft), address(nft));
        (address configuredNFT, address configuredBridge) = account.settings();
        assertEq(configuredNFT, address(nft));
        assertEq(configuredBridge, address(nft));
    }
}
