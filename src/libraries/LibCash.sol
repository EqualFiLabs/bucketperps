// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibUnits } from "./LibUnits.sol";

library LibCash {
    using SafeERC20 for IERC20;

    error InvalidAmount();
    error InvalidReceiver();
    error InexactTransfer();

    function receiveExact(address from, uint256 units) internal returns (uint256 wad) {
        if (units == 0) revert InvalidAmount();
        LibBookStorage.State storage b = LibBookStorage.state();
        IERC20 token = IERC20(b.settlementToken);
        uint256 beforeHere = token.balanceOf(address(this));
        uint256 beforeFrom = token.balanceOf(from);
        token.safeTransferFrom(from, address(this), units);
        if (
            token.balanceOf(address(this)) != beforeHere + units
                || token.balanceOf(from) + units != beforeFrom
        ) {
            revert InexactTransfer();
        }
        wad = LibUnits.toWad(units, b.cashQuantum);
        b.custodyWad += wad;
    }

    function sendExact(address to, uint256 wad) internal {
        if (wad == 0) revert InvalidAmount();
        if (to == address(0) || to == address(this)) revert InvalidReceiver();
        LibBookStorage.State storage b = LibBookStorage.state();
        uint256 units = LibUnits.toTokenUnits(wad, b.cashQuantum);
        IERC20 token = IERC20(b.settlementToken);
        uint256 beforeHere = token.balanceOf(address(this));
        uint256 beforeTo = token.balanceOf(to);
        b.custodyWad -= wad;
        token.safeTransfer(to, units);
        if (token.balanceOf(address(this)) + units != beforeHere || token.balanceOf(to) != beforeTo + units) {
            revert InexactTransfer();
        }
    }
}
