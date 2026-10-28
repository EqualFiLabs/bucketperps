// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { Test } from "forge-std/Test.sol";
import { DollarCoreMock } from "../mocks/DollarCoreMock.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { IStaticsDollarCore } from "../../src/interfaces/IStaticsDollarCore.sol";

contract DollarBoundaryTest is Test {
    function testSixDecimalCollateralRoundTripsThroughEighteenDecimalDollar() public {
        CashTokenMock usdg = new CashTokenMock(6);
        CashTokenMock dollar = new CashTokenMock(18);
        DollarCoreMock core = new DollarCoreMock(usdg, dollar);
        usdg.mint(address(this), 123_456_789);
        usdg.approve(address(core), 123_456_789);
        uint256 wad = 123_456_789e12;
        IStaticsDollarCore.PeggedMintPreview memory mintQuote = core.previewPeggedMint(1, wad);
        assertEq(mintQuote.totalCollateralIn, 123_456_789);
        assertEq(core.mintPegged(1, wad, 123_456_789, address(this)), 123_456_789);
        (IStaticsDollarCore.ExitStatus status, uint256 out) =
            core.redeemPegged(1, wad, 123_456_789, address(this));
        assertEq(uint256(status), 0);
        assertEq(out, 123_456_789);
        assertEq(usdg.balanceOf(address(this)), 123_456_789);
        assertEq(dollar.balanceOf(address(this)), 0);
    }
}
