// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { stdError } from "forge-std/StdError.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";

contract PnlHarness {
    function calculate(LibPnl.Position memory p, LibPnl.Curve memory c)
        external
        pure
        returns (int256, int256)
    {
        return LibPnl.calculate(p, c);
    }

    function bust(uint256 entry, uint32 leverage, uint64 buffer, bool isLong)
        external
        pure
        returns (uint256)
    {
        return LibPnl.bustPrice(entry, leverage, buffer, isLong);
    }
}

contract PnlTest is Test {
    PnlHarness internal harness = new PnlHarness();

    // JSON decoding uses alphabetical field order.
    struct Vector {
        bytes args;
        string id;
        bytes output;
        bool success;
    }

    struct ReferencePnl {
        uint64 entry;
        uint64 mark;
        uint128 margin;
        uint32 leverage;
        bool isLong;
        uint256 base;
        uint256 rate;
        uint256 position;
        uint256 notional;
        bool alternate;
    }

    function fixture() internal pure returns (LibPnl.Curve memory) {
        return LibPnl.Curve(0.02e18, 2e18, 1e18, 5e23, false);
    }

    function test_GoldenPnlOutputsInAdmittedDomain() public view {
        string memory json = vm.readFile("test/fixtures/pricing-vectors.json");
        Vector[] memory vectors = abi.decode(vm.parseJson(json, ".pnl"), (Vector[]));
        uint256 compared;
        for (uint256 i; i < vectors.length; ++i) {
            ReferencePnl memory r = abi.decode(vectors[i].args, (ReferencePnl));
            if (
                r.entry == 0 || r.mark == 0 || uint256(r.margin) * r.leverage > LibPnl.MAX_NOTIONAL
                    || r.base > 1e18 || r.rate > LibPnl.MAX_MULTIPLIER || r.position > LibPnl.MAX_MULTIPLIER
                    || r.notional > LibPnl.MAX_REFERENCE_NOTIONAL
            ) continue;
            LibPnl.Position memory p = LibPnl.Position(r.entry, r.mark, r.margin, r.leverage, r.isLong);
            LibPnl.Curve memory c = LibPnl.Curve(r.base, r.rate, r.position, r.notional, r.alternate);
            (int256 raw, int256 adjusted) = harness.calculate(p, c);
            assertTrue(vectors[i].success, vectors[i].id);
            assertEq(abi.encode(raw, adjusted), vectors[i].output, vectors[i].id);
            ++compared;
        }
        assertGe(compared, 145, "nonvacuous reference overlap");
    }

    function test_GoldenBustOutputsForUsableUntruncatedThresholds() public view {
        string memory json = vm.readFile("test/fixtures/pricing-vectors.json");
        uint256 compared;
        // Explicit typed readers avoid the JSON parser treating a 32-byte hex result as bytes32.
        for (uint256 i; i < 24; ++i) {
            string memory path = string.concat(".bust[", vm.toString(i), "]");
            (uint64 entry, uint32 leverage, uint64 buffer, bool isLong) = abi.decode(
                vm.parseJsonBytes(json, string.concat(path, ".args")), (uint64, uint32, uint64, bool)
            );
            if (
                entry < 1000 || entry > type(uint64).max / 2 || leverage < 2 || leverage > 1000
                    || buffer > 1e15
            ) continue;
            assertTrue(vm.parseJsonBool(json, string.concat(path, ".success")));
            bytes memory output = vm.parseJsonBytes(json, string.concat(path, ".output"));
            assertEq(harness.bust(entry, leverage, buffer, isLong), abi.decode(output, (uint64)));
            ++compared;
        }
        assertEq(compared, 6, "nonvacuous threshold overlap");
    }

    function test_NormalizedPricesRemainWideAndDoNotTruncate() public view {
        assertEq(harness.bust(100_000e18, 100, 5e14, true), 99_049.5e18);
        assertEq(harness.bust(100_000e18, 100, 5e14, false), 100_949.5e18);
        uint256 entry = type(uint64).max;
        assertEq(harness.bust(entry, 1, 0, false), 2 * entry);
        assertGt(harness.bust(entry, 1, 0, false), type(uint64).max);
        // Entry division and buffer division cannot be merged or applied to entry instead.
        assertEq(harness.bust(1_000_000_001, 3, 5e14, true), 667_000_001);
        assertEq(harness.bust(1_000_000_001, 3, 5e14, false), 1_332_666_668);
    }

    function test_BustPreservesCheckedFailuresAndReturnsZeroOrEntrySideThresholds() public {
        vm.expectRevert(stdError.divisionError);
        harness.bust(1e18, 0, 0, true);
        vm.expectRevert(stdError.arithmeticError);
        harness.bust(1e18, 100, 2e18, false);
        assertEq(harness.bust(1e18, 1, 0, true), 0);
        assertEq(harness.bust(1e18, 1000, 1e16, true), 1.00899e18);
        assertEq(harness.bust(1e18, 1000, 1e16, false), 0.99099e18);
        assertEq(harness.bust(100, 1000, 0, true), 100);
    }

    function test_AdversePnlHasNoWinningReductionAndLossCapIsSeparate() public view {
        LibPnl.Position memory p = LibPnl.Position(100e18, 99e18, 100e18, 10, true);
        (int256 raw, int256 adjusted) = harness.calculate(p, fixture());
        assertEq(raw, -10e18);
        assertEq(adjusted, -10e18);
        p.exitPrice = 1e18;
        (raw, adjusted) = harness.calculate(p, fixture());
        assertEq(raw, -990e18);
        assertEq(adjusted, -100e18);
    }

    function test_DeadZoneAndZeroImpactDenominators() public view {
        LibPnl.Position memory p = LibPnl.Position(100_000e18, 100_002e18, 100e18, 100, true);
        (int256 raw, int256 adjusted) = harness.calculate(p, fixture());
        assertEq(raw, 0);
        assertEq(adjusted, 0);
        ++p.exitPrice;
        LibPnl.Curve memory c = fixture();
        c.rateMultiplierWad = 0;
        (raw, adjusted) = harness.calculate(p, c);
        // Margin here is too small to turn a single price wei into nonzero USD PnL.
        assertEq(raw, 0);
        assertEq(adjusted, 0);
        p.exitPrice = 101_000e18;
        (raw, adjusted) = harness.calculate(p, c);
        assertGt(raw, 0);
        assertEq(adjusted, 0);
        c.rateMultiplierWad = 1e18;
        c.positionMultiplierWad = 0;
        (, adjusted) = harness.calculate(p, c);
        assertEq(adjusted, 0);
    }

    function test_ArithmeticDomainBoundaries() public {
        LibPnl.Position memory p =
            LibPnl.Position(LibPnl.MAX_PRICE, LibPnl.MAX_PRICE - 1, LibPnl.MAX_NOTIONAL, 1, true);
        harness.calculate(p, fixture());
        ++p.entryPrice;
        vm.expectRevert(LibPnl.InvalidPrice.selector);
        harness.calculate(p, fixture());
        p.entryPrice = 1e18;
        p.exitPrice = 2e18;
        p.marginWad = LibPnl.MAX_NOTIONAL + 1;
        vm.expectRevert(LibPnl.InvalidNotional.selector);
        harness.calculate(p, fixture());
        p.marginWad = 1e18;
        LibPnl.Curve memory c =
            LibPnl.Curve(1e18, type(uint96).max, type(uint96).max, type(uint128).max, true);
        (, int256 adjusted) = harness.calculate(p, c);
        assertEq(adjusted, 0);
        c.baseRateWad++;
        vm.expectRevert(LibPnl.InvalidCurve.selector);
        harness.calculate(p, c);
        c.baseRateWad = 0;
        c.rateMultiplierWad++;
        vm.expectRevert(LibPnl.InvalidCurve.selector);
        harness.calculate(p, c);
        c.rateMultiplierWad = 1;
        c.positionMultiplierWad++;
        vm.expectRevert(LibPnl.InvalidCurve.selector);
        harness.calculate(p, c);
        c.positionMultiplierWad = 1;
        c.referenceNotionalWad++;
        vm.expectRevert(LibPnl.InvalidCurve.selector);
        harness.calculate(p, c);
    }

    function test_WideWinningProductsUseFullPrecision() public view {
        LibPnl.Position memory p = LibPnl.Position(1, LibPnl.MAX_PRICE, LibPnl.MAX_NOTIONAL, 1, true);
        LibPnl.Curve memory c = LibPnl.Curve(0, LibPnl.MAX_MULTIPLIER, LibPnl.MAX_MULTIPLIER, 0, false);
        (int256 raw, int256 adjusted) = harness.calculate(p, c);
        assertEq(raw, int256(LibPnl.MAX_NOTIONAL * (LibPnl.MAX_PRICE - 1)));
        assertEq(adjusted, raw);
        // A naive final profit*retention product would exceed uint256 here.
        assertGt(uint256(raw), type(uint256).max / 1e18);

        p.entryPrice = 100_000e18;
        p.exitPrice = 100_002e18 + 1;
        c = fixture();
        c.rateMultiplierWad = 1;
        (raw, adjusted) = harness.calculate(p, c);
        assertGt(raw, 0);
        assertEq(adjusted, 0);
    }

    function testFuzz_WideDomainGainAndLossBounds(
        uint120 entrySeed,
        uint120 exitSeed,
        uint128 marginSeed,
        uint32 leverageSeed,
        bool isLong,
        uint256 baseSeed,
        uint96 rate,
        uint96 position,
        uint128 referenceNotional,
        bool alternate
    ) public pure {
        uint32 leverage = uint32(bound(leverageSeed, 1, type(uint32).max));
        LibPnl.Position memory p = LibPnl.Position(
            bound(entrySeed, 1, LibPnl.MAX_PRICE),
            bound(exitSeed, 1, LibPnl.MAX_PRICE),
            bound(marginSeed, 1, LibPnl.MAX_NOTIONAL / leverage),
            leverage,
            isLong
        );
        LibPnl.Curve memory c =
            LibPnl.Curve(bound(baseSeed, 0, 1e18), rate, position, referenceNotional, alternate);
        (int256 raw, int256 adjusted) = LibPnl.calculate(p, c);
        if (raw <= 0) {
            assertEq(adjusted, raw < -int256(p.marginWad) ? -int256(p.marginWad) : raw);
        } else {
            assertGe(adjusted, 0);
            assertLe(adjusted, raw);
        }
    }

    function testFuzz_FavorableMovementIsMonotonicAcrossBothCurves(
        uint120 entrySeed,
        uint32 lowSeed,
        uint32 highSeed,
        uint128 marginSeed,
        uint256 baseSeed,
        uint96 rate,
        uint96 position,
        uint128 referenceNotional,
        bool alternate,
        bool isLong
    ) public pure {
        uint256 entry = bound(entrySeed, 1, LibPnl.MAX_PRICE / 2);
        uint256 a = bound(lowSeed, 0, 10_000);
        uint256 b = bound(highSeed, a, 10_000);
        uint256 deltaA = entry * a / 1e6;
        uint256 deltaB = entry * b / 1e6;
        LibPnl.Position memory p = LibPnl.Position(
            entry,
            isLong ? entry + deltaA : entry - deltaA,
            bound(marginSeed, 1, LibPnl.MAX_NOTIONAL / 100),
            100,
            isLong
        );
        LibPnl.Curve memory c =
            LibPnl.Curve(bound(baseSeed, 0, 1e18), rate, position, referenceNotional, alternate);
        (, int256 lower) = LibPnl.calculate(p, c);
        p.exitPrice = isLong ? entry + deltaB : entry - deltaB;
        (, int256 higher) = LibPnl.calculate(p, c);
        assertGe(higher, lower);
    }

    function testFuzz_BustIsInclusiveAndStartsBeyondEntry(
        uint120 entrySeed,
        uint32 leverageSeed,
        uint64 bufferSeed,
        bool isLong
    ) public pure {
        uint32 leverage = uint32(bound(leverageSeed, 2, type(uint32).max));
        uint256 entry = bound(entrySeed, 2 * uint256(leverage), LibPnl.MAX_PRICE / 2);
        uint64 buffer = uint64(bound(bufferSeed, 0, 1e18 / (2 * uint256(leverage))));
        uint256 threshold = LibPnl.bustPrice(entry, leverage, buffer, isLong);
        assertTrue(LibPnl.isBusted(threshold, threshold, isLong));
        assertFalse(LibPnl.isBusted(entry, threshold, isLong));
        assertFalse(LibPnl.isBusted(isLong ? threshold + 1 : threshold - 1, threshold, isLong));
        assertTrue(LibPnl.isBusted(isLong ? threshold - 1 : threshold + 1, threshold, isLong));
    }
}
