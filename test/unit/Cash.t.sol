// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { CashFacet } from "../../src/facets/CashFacet.sol";
import { AccountFacet } from "../../src/facets/AccountFacet.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { LibCash } from "../../src/libraries/LibCash.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibUnits } from "../../src/libraries/LibUnits.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";

contract CashHarness is CashFacet, AccountFacet {
    constructor(address nft, address token) {
        LibAccountsStorage.state().positionNFT = nft;
        LibAccountsStorage.state().staticsDiamond = nft;
        LibBookStorage.state().settlementToken = token;
        LibBookStorage.state().cashQuantum = LibUnits.tokenQuantum(token);
    }

    function book() external view returns (LibBookStorage.State memory) {
        return LibBookStorage.state();
    }
}

contract CashTest is Test {
    CashTokenMock internal token;
    StaticsAccountMock internal statics;
    CashHarness internal cash;
    address internal alice;
    address internal bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new CashTokenMock(6);
        statics = new StaticsAccountMock();
        statics.mint(alice, 1);
        cash = new CashHarness(address(statics), address(token));
        statics.configure(address(cash), true);
        token.mint(alice, 1_000_000e6);
        vm.prank(alice);
        token.approve(address(cash), type(uint256).max);
    }

    function testFuzz_DepositWithdrawalConservesCustodyAndHouse(uint64 unitsSeed) public {
        uint256 units = bound(unitsSeed, 1, 1_000_000e6);
        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        cash.deposit(1, units);
        assertEq(cash.book().custodyWad, units * 1e12);
        assertEq(cash.book().accountCashWad, units * 1e12);
        assertEq(cash.book().realizedHousePnlWad, 0);
        assertEq(statics.activeLegCount(1), 1);
        vm.prank(alice);
        cash.withdraw(1, units * 1e12, alice);
        assertEq(token.balanceOf(alice), before);
        assertEq(token.balanceOf(address(cash)), 0);
        assertEq(cash.book().custodyWad, 0);
        assertEq(cash.book().accountCashWad, 0);
        assertEq(cash.book().realizedHousePnlWad, 0);
        assertEq(statics.activeLegCount(1), 0);
    }

    function test_InexactDepositsAndWithdrawalsRollBack() public {
        token.configure(1, false, address(0), "");
        vm.prank(alice);
        vm.expectRevert(LibCash.InexactTransfer.selector);
        cash.deposit(1, 100e6);
        assertEq(cash.book().custodyWad, 0);
        assertEq(token.balanceOf(alice), 1_000_000e6);
        token.configure(0, false, address(0), "");
        vm.prank(alice);
        cash.deposit(1, 100e6);
        token.configure(1, false, address(0), "");
        vm.prank(alice);
        vm.expectRevert(LibCash.InexactTransfer.selector);
        cash.withdraw(1, 100e18, bob);
        assertEq(cash.accountState(1).cashWad, 100e18);
        assertEq(token.balanceOf(address(cash)), 100e6);
    }

    function test_TransferAndMarkerFailureAreAtomic() public {
        statics.setFailure(true, address(0), "");
        vm.prank(alice);
        vm.expectRevert();
        cash.deposit(1, 100e6);
        assertEq(token.balanceOf(alice), 1_000_000e6);
        assertEq(token.balanceOf(address(cash)), 0);
        statics.setFailure(false, address(0), "");
        vm.prank(alice);
        cash.deposit(1, 100e6);
        token.configure(0, true, address(0), "");
        vm.prank(alice);
        vm.expectRevert();
        cash.withdraw(1, 100e18, bob);
        assertEq(cash.book().accountCashWad, 100e18);
        assertEq(cash.book().custodyWad, 100e18);
    }

    function test_ApprovalsCannotWithdrawAndTransferChangesOwner() public {
        vm.prank(alice);
        cash.deposit(1, 100e6);
        vm.prank(alice);
        statics.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        cash.withdraw(1, 100e18, bob);
        vm.prank(bob);
        statics.transferFrom(alice, bob, 1);
        vm.prank(bob);
        cash.withdraw(1, 100e18, bob);
        assertEq(token.balanceOf(bob), 100e6);
    }

    function test_TokenCallbackAndNonrepresentableExitRevert() public {
        token.configure(0, false, address(cash), abi.encodeCall(AccountFacet.syncAccountActivity, (1)));
        vm.prank(alice);
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        cash.deposit(1, 100e6);
        token.configure(0, false, address(0), "");
        vm.prank(alice);
        cash.deposit(1, 100e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LibUnits.InexactAmount.selector, 1, 1e12));
        cash.withdraw(1, 1, alice);
        assertEq(cash.book().accountCashWad, 100e18);
    }

    function test_DonationsDoNotCreditCashOrHousePnL() public {
        token.mint(address(cash), 20e6);
        assertEq(cash.book().custodyWad, 0);
        assertEq(cash.book().accountCashWad, 0);
        assertEq(cash.book().realizedHousePnlWad, 0);
    }
}
