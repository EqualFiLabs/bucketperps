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
