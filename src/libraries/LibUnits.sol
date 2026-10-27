// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice USD/price amounts use WAD; rewards remain raw token units.
library LibUnits {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;

    error UnsupportedDecimals(uint8 decimals);
    error InvalidToken();
    error InvalidQuantum();
    error InexactAmount(uint256 amountWad, uint256 quantum);
    error InvalidBasisPoints();

    /// @dev Token identity and deployment metadata are separately qualified at bootstrap.
    function tokenQuantum(address token) internal view returns (uint256) {
        if (token.code.length == 0) revert InvalidToken();
        return quantum(IERC20Metadata(token).decimals());
    }

    function quantum(uint8 decimals) internal pure returns (uint256) {
        if (decimals > 18) revert UnsupportedDecimals(decimals);
        return 10 ** (18 - decimals);
    }

    function toWad(uint256 tokenUnits, uint256 cashQuantum) internal pure returns (uint256) {
        _requireQuantum(cashQuantum);
        return tokenUnits * cashQuantum;
    }

    function toTokenUnits(uint256 amountWad, uint256 cashQuantum) internal pure returns (uint256) {
        _requireQuantum(cashQuantum);
        if (amountWad % cashQuantum != 0) revert InexactAmount(amountWad, cashQuantum);
        return amountWad / cashQuantum;
    }

    function floorCash(uint256 amountWad, uint256 cashQuantum) internal pure returns (uint256) {
        _requireQuantum(cashQuantum);
        return amountWad - amountWad % cashQuantum;
    }

    function mulDivCash(uint256 x, uint256 y, uint256 denominator, uint256 cashQuantum)
        internal
        pure
        returns (uint256)
    {
        return floorCash(Math.mulDiv(x, y, denominator), cashQuantum);
    }

    function fee(uint256 basisWad, uint256 feeBps, uint256 cashQuantum) internal pure returns (uint256) {
        if (feeBps > BPS) revert InvalidBasisPoints();
        return mulDivCash(basisWad, feeBps, BPS, cashQuantum);
    }

    /// @dev The rate numerator is raw receipt units per WAD of USD loss.
    function rewardUnits(uint256 lossBasisWad, uint256 rawUnitsPerDollar) internal pure returns (uint256) {
        return Math.mulDiv(lossBasisWad, rawUnitsPerDollar, WAD);
    }

    function _requireQuantum(uint256 cashQuantum) private pure {
        // Configured quanta originate in quantum(); reject accidental zero use.
        if (cashQuantum == 0) revert InvalidQuantum();
    }
}
