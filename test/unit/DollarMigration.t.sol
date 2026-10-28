// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { DollarProtocolFixture } from "../helpers/DollarProtocolFixture.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { IStaticsDollarCore } from "../../src/interfaces/IStaticsDollarCore.sol";

contract DollarMigrationTest is DollarProtocolFixture {
    function testMigrationPreservesWadBookAndUnassignedDonations() public {
        _house(100e18);
        token.mint(address(diamond), 7e6);
        _openCash(1, alice, true);
        uint256 claim = bookView.seedEntitlement(2, 100e18);
        _openClaim(2, bob, claim);
        LibBookStorage.State memory beforeBook = bookView.book();
        _bindDollar();
        _migrate();
        LibBookStorage.State memory afterBook = bookView.book();
        assertEq(afterBook.cashQuantum, 1);
        assertEq(afterBook.settlementToken, address(dollar));
        afterBook.cashQuantum = beforeBook.cashQuantum;
        afterBook.settlementToken = beforeBook.settlementToken;
        assertEq(abi.encode(afterBook), abi.encode(beforeBook));
        assertEq(dollar.balanceOf(address(diamond)), beforeBook.custodyWad + 7e18);
        assertEq(token.balanceOf(address(diamond)), 0);
        assertEq(token.allowance(address(diamond), address(dollarCore)), 0);
        vm.expectRevert();
        assetFacet.migrateUsdGToUsdStx();
    }

    function testOwnerUsdGRedemptionAndNativeFinePrecisionExit() public {
        _bindDollar();
        _migrate();
        vm.prank(bob);
        vm.expectRevert();
        assetFacet.withdrawUsdG(1, 10e18, bob);
        vm.prank(alice);
        assetFacet.withdrawUsdG(1, 10e18, alice);
        assertEq(token.balanceOf(alice), 10e6);
        assertEq(accounts.accountState(1).cashWad, 990e18);
        // Fine USDstx precision can be deposited, and remains credited on an inexact USDG request.
        dollar.mint(alice, 1);
        vm.startPrank(alice);
        dollar.approve(address(diamond), 1);
        cash.deposit(1, 1);
        vm.expectRevert();
        assetFacet.withdrawUsdG(1, 1, alice);
        assertEq(accounts.accountState(1).cashWad, 990e18 + 1);
        cash.withdraw(1, 1, alice);
        vm.stopPrank();
        assertEq(dollar.balanceOf(alice), 1);
    }

    function testRedemptionFailureRollsBackAccountAndPhysicalCustody() public {
        _bindDollar();
        _migrate();
        dollarCore.configure(0, IStaticsDollarCore.ExitStatus.Recovering, false);
        vm.prank(alice);
        vm.expectRevert();
        assetFacet.withdrawUsdG(1, 10e18, alice);
        assertEq(accounts.accountState(1).cashWad, 1000e18);
        assertEq(dollar.balanceOf(address(diamond)), 2000e18);
        dollarCore.configure(0, IStaticsDollarCore.ExitStatus.Available, true);
        vm.prank(alice);
        vm.expectRevert();
        assetFacet.withdrawUsdG(1, 10e18, alice);
        assertEq(accounts.accountState(1).cashWad, 1000e18);
        assertEq(dollar.balanceOf(address(diamond)), 2000e18);
        assertEq(token.balanceOf(alice), 0);
    }

    function testLiveBookMigrationAfterFinalizationPreservesRewardsDebtFeesAndOldTrades() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        _earnReceipts(2, bob);
        uint256 cashTrade = _openCash(1, alice, true);
        uint256 claim = bookView.seedEntitlement(2, 200e18);
        uint256 claimTrade = _openClaim(2, bob, claim);
        uint256 lossTrade = _openCash(2, bob, true);
        _price(49_900e18);
        vm.prank(bob);
        settlement.closePosition(2, lossTrade, block.timestamp, new bytes[](0));
        assertGt(bookView.book().sideBucketWad, 0);
        LibBookStorage.State memory beforeBook = bookView.book();
        bytes32 accountOne = keccak256(abi.encode(accounts.accountState(1)));
        bytes32 accountTwo = keccak256(abi.encode(accounts.accountState(2)));
        uint256 pending = staking.pendingStakerRevenue(1);
        uint256 backing = staticsToken.balanceOf(rewards.rewardState().backingVault);
        _bindDollar();
        controls.finalizeProtocol();
        _migrate();
        LibBookStorage.State memory afterBook = bookView.book();
        afterBook.settlementToken = beforeBook.settlementToken;
        afterBook.cashQuantum = beforeBook.cashQuantum;
        assertEq(abi.encode(afterBook), abi.encode(beforeBook));
        assertEq(keccak256(abi.encode(accounts.accountState(1))), accountOne);
        assertEq(keccak256(abi.encode(accounts.accountState(2))), accountTwo);
        assertEq(staking.pendingStakerRevenue(1), pending);
        assertEq(staticsToken.balanceOf(rewards.rewardState().backingVault), backing);
        vm.prank(alice);
        settlement.closePosition(1, cashTrade, block.timestamp, new bytes[](0));
        vm.prank(bob);
        settlement.closePosition(2, claimTrade, block.timestamp, new bytes[](0));
        vm.prank(alice);
        staking.claimStakerRevenue(1);
        queue.harvest(128);
        assertEq(bookView.book().committedDebtWad, 0);
        assertEq(dollar.balanceOf(address(diamond)), bookView.book().custodyWad);
    }

    function testFeeQuoteRejectsBindingAndLaterMigrationWithoutLosingCash() public {
        dollarCore.configure(1, IStaticsDollarCore.ExitStatus.Available, false);
        controls.scheduleSafetyAction(
            keccak256(abi.encode("dollar-binding", address(dollarCore), address(dollar), uint256(1)))
        );
        vm.expectRevert();
        assetFacet.configureDollarMigration(address(dollarCore), address(dollar), 1);
        assertEq(assetFacet.dollarMigrationState().core, address(0));
        dollarCore.configure(0, IStaticsDollarCore.ExitStatus.Available, false);
        _bindDollar();
        dollarCore.configure(1, IStaticsDollarCore.ExitStatus.Available, false);
        controls.scheduleSafetyAction(
            keccak256(abi.encode("dollar-migration", address(dollarCore), address(dollar), uint256(1)))
        );
        vm.expectRevert();
        assetFacet.migrateUsdGToUsdStx();
        assertEq(token.balanceOf(address(diamond)), 2000e6);
        assertFalse(assetFacet.dollarMigrationState().migrated);
    }

    function testInexactMigrationRollsBackEverything() public {
        _bindDollar();
        dollarCore.configure(0, IStaticsDollarCore.ExitStatus.Available, true);
        controls.scheduleSafetyAction(
            keccak256(abi.encode("dollar-migration", address(dollarCore), address(dollar), uint256(1)))
        );
        vm.expectRevert();
        assetFacet.migrateUsdGToUsdStx();
        assertFalse(assetFacet.dollarMigrationState().migrated);
        assertEq(bookView.book().settlementToken, address(token));
        assertEq(token.balanceOf(address(diamond)), 2000e6);
        assertEq(dollar.balanceOf(address(diamond)), 0);
    }
}
