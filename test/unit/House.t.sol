// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibCash } from "../../src/libraries/LibCash.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";
import { HouseFacet } from "../../src/facets/HouseFacet.sol";

contract HouseTest is ProtocolFixture {
    function test_DonationsRequireExplicitClassificationAndCannotCreateTradingProfit() public {
        token.mint(address(diamond), 10e6);
        assertEq(houseFacet.unassignedSettlementUnits(), 10e6);
        assertEq(bookView.book().custodyWad, 2_000e18);
        vm.prank(alice);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        houseFacet.classifySettlementDonation(10e18);
        houseFacet.classifySettlementDonation(10e18);
        assertEq(bookView.book().custodyWad, 2_010e18);
        assertEq(bookView.book().realizedHousePnlWad, 0);
        assertEq(houseFacet.unassignedSettlementUnits(), 0);
        houseFacet.configureSurplus(1e18, alice, bob, 2_000);
        vm.expectRevert(HouseFacet.SurplusUnavailable.selector);
        houseFacet.distributeSurplus(1e18);
    }

    function test_QueueBlocksSurplusButCommittedClaimMarginDoesNot() public {
        _house(1_000e18);
        houseFacet.configureSurplus(10e18, alice, bob, 2_000);
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        vm.expectRevert(HouseFacet.SurplusUnavailable.selector);
        houseFacet.distributeSurplus(1e18);
        _openClaim(1, alice, claimId);
        assertEq(bookView.book().queuedDebtWad, 0);
        assertEq(bookView.book().committedDebtWad, 100e18);
        houseFacet.distributeSurplus(1e18);
        assertEq(token.balanceOf(alice), 800_000);
        assertEq(token.balanceOf(bob), 200_000);
        assertEq(bookView.book().committedDebtWad, 100e18);
        assertEq(bookView.book().custodyWad, 2_999e18);
        assertEq(bookView.book().accountCashWad, 2_000e18);
    }

    function test_SurplusWorksWithDefaultPlaceholdersWithoutAnEnableStep() public {
        _house(100e18);
        houseFacet.distributeSurplus(40e18);
        assertEq(token.balanceOf(address(this)), 40e6);
        assertEq(bookView.book().custodyWad, 2_060e18);
        assertEq(bookView.book().realizedHousePnlWad, 60e18);
        vm.prank(alice);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        houseFacet.configureSurplus(10e18, alice, bob, 2_000);
    }

    function test_DistributionPreservesAccountCashLockedMarginAndFundedFees() public {
        _house(100e18);
        uint256 id = _openCash(1, alice, true);
        _openCash(2, bob, false);
        _price(49_900e18);
        vm.prank(alice);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        LibBookStorage.State memory beforeBook = bookView.book();
        houseFacet.distributeSurplus(100e18);
        LibBookStorage.State memory afterBook = bookView.book();
        assertEq(afterBook.custodyWad, beforeBook.custodyWad - 100e18);
        assertEq(afterBook.realizedHousePnlWad, beforeBook.realizedHousePnlWad - 100e18);
        assertEq(afterBook.accountCashWad, beforeBook.accountCashWad);
        assertEq(afterBook.lockedCashMarginWad, 100e18);
        assertEq(afterBook.fundedPayablesWad, 0.2e18);
        assertEq(token.balanceOf(address(diamond)) * 1e12, afterBook.custodyWad);
    }

    function test_SurplusDecreasesCashAndProfitOnceAndConservesSplit() public {
        _house(100e18);
        houseFacet.configureSurplus(10e18, alice, bob, 2_000);
        houseFacet.distributeSurplus(40e18);
        assertEq(token.balanceOf(alice), 32e6);
        assertEq(token.balanceOf(bob), 8e6);
        assertEq(bookView.book().custodyWad, 2_060e18);
        assertEq(bookView.book().accountCashWad, 2_000e18);
        assertEq(bookView.book().realizedHousePnlWad, 60e18);
        vm.expectRevert(HouseFacet.SurplusUnavailable.selector);
        houseFacet.distributeSurplus(60e18);
        assertEq(bookView.book().custodyWad, 2_060e18);
    }

    function test_InexactSurplusTransferRollsBackProfitAndBothRecipients() public {
        _house(100e18);
        houseFacet.configureSurplus(10e18, alice, bob, 2_000);
        token.configure(1, false, address(0), "");
        vm.expectRevert(LibCash.InexactTransfer.selector);
        houseFacet.distributeSurplus(40e18);
        assertEq(bookView.book().custodyWad, 2_100e18);
        assertEq(bookView.book().realizedHousePnlWad, 100e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_CustodyShortfallFailsClosedWithoutWritingDownUserBalances() public {
        token.burn(address(diamond), 1);
        vm.expectRevert(LibCash.CustodyShortfall.selector);
        houseFacet.unassignedSettlementUnits();
        vm.prank(alice);
        vm.expectRevert(LibCash.CustodyShortfall.selector);
        cash.withdraw(1, 1e18, alice);
        vm.expectRevert(LibCash.CustodyShortfall.selector);
        queue.harvest(1);
        assertEq(bookView.book().custodyWad, 2_000e18);
        assertEq(accounts.accountState(1).cashWad, 1_000e18);
    }
}
