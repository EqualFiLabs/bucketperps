// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { stdError } from "forge-std/StdError.sol";
import { LibUnits } from "../../src/libraries/LibUnits.sol";

contract DecimalToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract UnitsHarness {
    function tokenQuantum(address token) external view returns (uint256) {
        return LibUnits.tokenQuantum(token);
    }

    function quantum(uint8 decimals) external pure returns (uint256) {
        return LibUnits.quantum(decimals);
    }

    function toWad(uint256 amount, uint256 q) external pure returns (uint256) {
        return LibUnits.toWad(amount, q);
    }

    function toTokenUnits(uint256 amount, uint256 q) external pure returns (uint256) {
        return LibUnits.toTokenUnits(amount, q);
    }

    function fee(uint256 amount, uint256 bps, uint256 q) external pure returns (uint256) {
        return LibUnits.fee(amount, bps, q);
    }

    function mulDiv(uint256 x, uint256 y, uint256 d, uint256 q) external pure returns (uint256) {
        return LibUnits.mulDivCash(x, y, d, q);
    }
}

contract UnitsTest is Test {
    UnitsHarness internal harness = new UnitsHarness();

    function testFuzz_ExactTokenRoundTrip(uint256 rawAmount, uint8 rawDecimals) public pure {
        uint8 decimals = uint8(bound(rawDecimals, 0, 18));
        uint256 q = LibUnits.quantum(decimals);
        uint256 amount = bound(rawAmount, 0, type(uint256).max / q);
        uint256 wadAmount = LibUnits.toWad(amount, q);
        assertEq(LibUnits.toTokenUnits(wadAmount, q), amount);
        assertEq(wadAmount % q, 0);
    }

    function testFuzz_FloorCashNeverAddsValueAndLosesLessThanQuantum(uint256 amount, uint8 rawDecimals)
        public
        pure
    {
        uint256 q = LibUnits.quantum(uint8(bound(rawDecimals, 0, 18)));
        uint256 rounded = LibUnits.floorCash(amount, q);
        assertLe(rounded, amount);
        assertLt(amount - rounded, q);
        assertEq(rounded % q, 0);
    }

    function testFuzz_FeesAreBoundedAndRepresentable(uint256 amount, uint16 rawBps, uint8 rawDecimals)
        public
        pure
    {
        uint256 bps = bound(rawBps, 0, 10_000);
        uint256 q = LibUnits.quantum(uint8(bound(rawDecimals, 0, 18)));
        uint256 value = LibUnits.fee(amount, bps, q);
        assertLe(value, amount);
        assertEq(value % q, 0);
        // Independently bound the discarded fee fraction using quotient/remainder arithmetic.
        uint256 referenceFloor = (amount / 10_000) * bps + ((amount % 10_000) * bps) / 10_000;
        assertLe(value, referenceFloor);
        assertLt(referenceFloor - value, q);
    }

    function test_MetadataIsReadRatherThanAssumed() public {
        DecimalToken six = new DecimalToken(6);
        DecimalToken eighteen = new DecimalToken(18);
        DecimalToken unsupported = new DecimalToken(19);
        assertEq(harness.tokenQuantum(address(six)), 1e12);
        assertEq(harness.tokenQuantum(address(eighteen)), 1);
        vm.expectRevert(abi.encodeWithSelector(LibUnits.UnsupportedDecimals.selector, uint8(19)));
        harness.tokenQuantum(address(unsupported));
        vm.expectRevert(LibUnits.InvalidToken.selector);
        harness.tokenQuantum(address(0));
    }

    function test_ExactAndAdjacentCashBoundaries() public {
        uint256 q = 1e12; // Six-decimal fixture; not production metadata.
        assertEq(harness.toTokenUnits(q, q), 1);
        vm.expectRevert(abi.encodeWithSelector(LibUnits.InexactAmount.selector, q - 1, q));
        harness.toTokenUnits(q - 1, q);
        vm.expectRevert(abi.encodeWithSelector(LibUnits.InexactAmount.selector, q + 1, q));
        harness.toTokenUnits(q + 1, q);
        vm.expectRevert(LibUnits.InvalidQuantum.selector);
        harness.toWad(1, 0);
        vm.expectRevert(LibUnits.InvalidQuantum.selector);
        harness.toTokenUnits(0, 0);
    }

    function test_FullPrecisionIntermediateProductAndOverflow() public {
        uint256 maximum = type(uint256).max;
        assertEq(harness.mulDiv(maximum, maximum, maximum, 1), maximum);
        assertEq(harness.fee(maximum, 10_000, 1), maximum);
        vm.expectRevert(stdError.arithmeticError);
        harness.toWad(maximum, 10);
    }

    function test_RewardRateUsesRawUnitsWithoutAssumingReceiptDecimals() public pure {
        assertEq(LibUnits.rewardUnits(125e16, 100e6), 125e6);
        assertEq(LibUnits.rewardUnits(125e16, 100e18), 125e18);
        assertEq(LibUnits.rewardUnits(1, 1), 0);
        assertEq(LibUnits.rewardUnits(type(uint256).max, 1e18), type(uint256).max);
    }

    function test_InvalidConfigurationBoundaries() public {
        assertEq(harness.quantum(18), 1);
        vm.expectRevert(abi.encodeWithSelector(LibUnits.UnsupportedDecimals.selector, uint8(19)));
        harness.quantum(19);
        vm.expectRevert(LibUnits.InvalidBasisPoints.selector);
        harness.fee(1e18, 10_001, 1);
    }
}
