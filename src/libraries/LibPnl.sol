// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Directional PnL and the contract-set-2 winning curve at normalized price precision.
/// @dev Price and notional ceilings are arithmetic limits, not calibrated market settings.
library LibPnl {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_PRICE = type(uint120).max;
    uint256 internal constant MAX_NOTIONAL = type(uint128).max;
    uint256 internal constant MAX_MULTIPLIER = type(uint96).max;
    uint256 internal constant MAX_REFERENCE_NOTIONAL = type(uint128).max;

    struct Position {
        uint256 entryPrice;
        uint256 exitPrice;
        uint256 marginWad;
        uint32 leverage;
        bool isLong;
    }

    struct Curve {
        uint256 baseRateWad;
        uint256 rateMultiplierWad;
        uint256 positionMultiplierWad;
        uint256 referenceNotionalWad;
        bool alternate;
    }

    error InvalidPrice();
    error InvalidNotional();
    error InvalidCurve();

    function validatePrice(uint256 price) internal pure {
        if (price == 0 || price > MAX_PRICE) revert InvalidPrice();
    }

    function validateCurve(Curve memory c) internal pure {
        if (
            c.baseRateWad > WAD || c.rateMultiplierWad > MAX_MULTIPLIER
                || c.positionMultiplierWad > MAX_MULTIPLIER || c.referenceNotionalWad > MAX_REFERENCE_NOTIONAL
        ) revert InvalidCurve();
    }

    /// @dev Both divisions remain independent; the buffer is applied to boundary, not entry.
    /// The uint64 reference's final narrowing is intentionally absent at normalized precision.
    /// Zero leverage retains Solidity's division-by-zero panic for a valid entry price.
    function bustPrice(uint256 entryPrice, uint32 leverage, uint64 bufferWad, bool isLong)
        internal
        pure
        returns (uint256 threshold)
    {
        validatePrice(entryPrice);
        uint256 distance = entryPrice / leverage;
        uint256 boundary = isLong ? entryPrice - distance : entryPrice + distance;
        uint256 adjustment = boundary * bufferWad / WAD;
        threshold = isLong ? boundary + adjustment : boundary - adjustment;
    }

    function isBusted(uint256 price, uint256 threshold, bool isLong) internal pure returns (bool) {
        return isLong ? price <= threshold : price >= threshold;
    }

    /// @notice Returns unquantized signed USD values. Settlement applies the cash quantum once.
    /// @dev Bust takes precedence in the caller. This function alone caps ordinary adverse PnL.
    function calculate(Position memory p, Curve memory c)
        internal
        pure
        returns (int256 rawPnl, int256 adjustedPnl)
    {
        validatePrice(p.entryPrice);
        validatePrice(p.exitPrice);
        validateCurve(c);
        uint256 notional = p.marginWad * p.leverage;
        if (notional == 0 || notional > MAX_NOTIONAL) revert InvalidNotional();

        uint256 deadZone = p.entryPrice / 50_000;
        bool favorable = p.isLong ? p.exitPrice > p.entryPrice : p.exitPrice < p.entryPrice;
        uint256 movement =
            p.exitPrice > p.entryPrice ? p.exitPrice - p.entryPrice : p.entryPrice - p.exitPrice;
        uint256 effectiveMove = favorable ? (movement > deadZone ? movement - deadZone : 0) : movement;
        // notional <= 128 bits and movement <= 120 bits: the signed product fits in 248 bits.
        rawPnl = int256(notional) * (favorable ? int256(effectiveMove) : -int256(effectiveMove))
            / int256(p.entryPrice);
        if (rawPnl <= 0) {
            int256 floor = -int256(p.marginWad);
            return (rawPnl, rawPnl < floor ? floor : rawPnl);
        }

        uint256 carved = _carvedMovement(p.entryPrice, movement, deadZone, c.alternate);
        if (carved == 0) {
            return (rawPnl, int256(_impact(uint256(rawPnl), effectiveMove * WAD / p.entryPrice, c)));
        }
        // Full-precision products keep the widened domain usable without collapsing any floors.
        uint256 carvedPnl = Math.mulDiv(notional, carved, WAD);
        adjustedPnl = int256(_impact(carvedPnl, carved, c));
    }

    function _carvedMovement(uint256 entry, uint256 movement, uint256 deadZone, bool alternate)
        private
        pure
        returns (uint256)
    {
        uint256 start = entry * (alternate ? 30 : 75) / 1e6;
        uint256 end = entry * (alternate ? 1000 : 600) / 1e6;
        if (movement <= start || movement >= end) return 0;
        uint256 width = end - start;
        uint256 u = (movement - start) * WAD / width;
        uint256 shape = u * (WAD - u) / WAD;
        shape = shape * shape / WAD;
        if (alternate) shape = shape * (WAD - u) / WAD;
        uint256 coefficient = alternate ? 6085e15 : 3597e15;
        // With a 120-bit price, the unreduced product occupies fewer than 244 bits.
        uint256 reduction = coefficient * width * shape / WAD;
        return ((movement - deadZone) * WAD - reduction) / entry;
    }

    function _impact(uint256 profit, uint256 movementWad, Curve memory c) private pure returns (uint256) {
        uint256 rateDenominator = Math.mulDiv(movementWad, c.rateMultiplierWad, WAD);
        uint256 impactRate = rateDenominator == 0 ? type(uint256).max : 1e36 / rateDenominator;
        uint256 positionDenominator = Math.mulDiv(movementWad, 1e6 * c.positionMultiplierWad, WAD);
        uint256 impactPosition =
            positionDenominator == 0 ? type(uint256).max : c.referenceNotionalWad * WAD / positionDenominator;
        if (impactRate > 1e36 || impactPosition > 1e36) return 0;
        uint256 retention = (WAD - c.baseRateWad) * WAD / (WAD + impactRate + impactPosition);
        return Math.mulDiv(profit, retention, WAD);
    }
}
