// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibFees } from "../../src/libraries/LibFees.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibUnits } from "../../src/libraries/LibUnits.sol";
import { LibSettlement } from "../../src/libraries/LibSettlement.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";

contract FeeMathHarness {
    function quote(uint256 basis, uint16 staker, uint16 protocol, uint16 operator, uint8 decimals)
        external
        returns (LibFees.Quote memory)
    {
        LibBookStorage.state().cashQuantum = LibUnits.quantum(decimals);
        LibMarkets.FeeTerms memory f;
        f.winStakerBps = staker;
        f.winProtocolBps = protocol;
        f.winOperatorBps = operator;
        return LibFees.quote(basis, f, true);
    }
}

contract FeeMathTest is Test {
    FeeMathHarness internal math = new FeeMathHarness();

    function testFuzz_SplitConservesAggregateAndQuantum(
        uint128 basis,
        uint16 stakerSeed,
        uint16 protocolSeed,
        uint16 operatorSeed,
        uint8 decimalsSeed
    ) public {
        stakerSeed = uint16(bound(stakerSeed, 0, 10_000));
        protocolSeed = uint16(bound(protocolSeed, 0, 10_000 - stakerSeed));
        operatorSeed = uint16(bound(operatorSeed, 0, 10_000 - stakerSeed - protocolSeed));
        decimalsSeed = uint8(bound(decimalsSeed, 0, 18));
        LibFees.Quote memory q = math.quote(basis, stakerSeed, protocolSeed, operatorSeed, decimalsSeed);
        uint256 quantum = 10 ** (18 - decimalsSeed);
        uint256 totalBps = uint256(stakerSeed) + protocolSeed + operatorSeed;
        uint256 independentlyRounded = uint256(basis) * totalBps / 10_000 / quantum * quantum;
        assertEq(q.totalWad, independentlyRounded);
        assertEq(q.stakerWad + q.protocolWad + q.operatorWad, q.totalWad);
        assertEq(q.totalWad % quantum, 0);
        assertEq(q.stakerWad % quantum, 0);
        assertEq(q.operatorWad % quantum, 0);
        assertLe(q.totalWad, basis);
    }
}

contract FeeFundingTest is ProtocolFixture {
    function test_ZeroWeightRetainsSliceButPreservesFullFeeEligibilityBoundary() public {
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        uint256 id = _openClaim(1, alice, claimId);
        _house(80.3e18); // Survivor $80 + full fee $0.40 does not fit.
        _price(49_900e18);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.entitlement.paidWad, 80e18);
        assertEq(r.quotedFeeWad, 0.4e18);
        assertEq(r.fundedFeeWad, 0);
        assertEq(bookView.book().fundedPayablesWad, 0);
        assertEq(feeFacet.feePayables().stakerPayableWad, 0);
    }

    function test_ExactSurvivorAndFullFeeFundsOnlyActualNonStakerLiabilities() public {
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        uint256 id = _openClaim(1, alice, claimId);
        _house(80.4e18);
        _price(49_900e18);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.entitlement.paidWad, 80e18);
        assertEq(r.fundedFeeWad, 0.2e18);
        assertEq(feeFacet.feePayables().protocolPayableWad, 0.16e18);
        assertEq(feeFacet.feePayables().operatorPayableWad, 0.04e18);
        assertEq(feeFacet.feePayables().stakerPayableWad, 0);
        assertEq(bookView.book().fundedPayablesWad, 0.2e18);
        uint256 house =
            bookView.book().custodyWad - bookView.book().accountCashWad - bookView.book().fundedPayablesWad;
        assertEq(house, 0.2e18);
    }

    function test_FundedFeesAreSegregatedAndDeliveryDoesNotRecognizePnlAgain() public {
        uint256 id = _openCash(1, alice, true);
        _price(49_900e18);
        vm.prank(alice);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        int256 beforeP = bookView.book().realizedHousePnlWad;
        uint256 beforeT = bookView.book().custodyWad;
        vm.prank(alice);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        feeFacet.withdrawProtocolFees(0.16e18, alice);
        token.configure(0, true, address(0), "");
        vm.expectRevert();
        feeFacet.withdrawProtocolFees(0.16e18, alice);
        assertEq(feeFacet.feePayables().protocolPayableWad, 0.16e18);
        assertEq(bookView.book().custodyWad, beforeT);
        token.configure(0, false, address(0), "");
        feeFacet.withdrawProtocolFees(0.16e18, alice);
        assertEq(feeFacet.feePayables().protocolPayableWad, 0);
        assertEq(bookView.book().custodyWad, beforeT - 0.16e18);
        assertEq(bookView.book().fundedPayablesWad, 0.04e18);
        assertEq(bookView.book().realizedHousePnlWad, beforeP);
    }
}
