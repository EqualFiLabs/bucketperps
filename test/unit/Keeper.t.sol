// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibKeeper } from "../../src/libraries/LibKeeper.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { FundingSource, OpenParams, ClaimPortion } from "../../src/types/TradingTypes.sol";

contract KeeperMathHarness {
    function quote(uint256 margin, uint16 rate, uint256 cap, uint256 funded, uint256 quantum)
        external
        pure
        returns (uint256)
    {
        return LibKeeper.quote(margin, rate, cap, funded, quantum);
    }
}

contract KeeperMathTest is Test {
    KeeperMathHarness internal math = new KeeperMathHarness();

    function testFuzz_CreditNeverExceedsCurrentFundedProtocolSlice(
        uint128 margin,
        uint16 rate,
        uint128 cap,
        uint128 fundedSeed,
        uint8 decimalSeed
    ) public {
        uint256 quantum = 10 ** (18 - bound(decimalSeed, 0, 18));
        uint256 funded = uint256(fundedSeed) / quantum * quantum;
        uint256 amount = math.quote(margin, rate, cap, funded, quantum);
        assertLe(amount, funded);
        assertLe(amount, cap);
        assertLe(amount, uint256(margin) * rate / 10_000);
        assertEq(amount % quantum, 0);
    }
}

contract KeeperFundingTest is ProtocolFixture {
    function test_RateAboveProtocolShareIsCappedByActualFundedProtocolFee() public {
        LibMarkets.Terms memory terms = _terms();
        terms.fees.keeperLossBps = type(uint16).max;
        terms.fees.keeperMaxWad = 100e18;
        markets.publishTerms(MARKET, terms);
        OpenParams memory params = _params(true, FundingSource.Cash);
        params.expectedTermsVersion = 2;
        vm.prank(alice);
        uint256 id = trading.openPosition(1, params, new ClaimPortion[](0), new bytes[](0));
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(address(this)), 0.8e18);
        assertEq(feeFacet.feePayables().protocolPayableWad, 0);
        assertEq(bookView.book().fundedPayablesWad, 1e18);
    }

    function test_KeeperCreditReclassifiesOnlyFundedProtocolFeeAndWithdrawsByOwner() public {
        uint256 id = _openCash(1, alice, true);
        _price(trading.tradeState(id).bustPrice1e18);
        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(keeper), 0.4e18);
        assertEq(feeFacet.feePayables().protocolPayableWad, 0.4e18);
        assertEq(feeFacet.feePayables().operatorPayableWad, 0.2e18);
        assertEq(bookView.book().fundedPayablesWad, 1e18);
        vm.prank(alice);
        vm.expectRevert();
        liquidation.withdrawKeeperCredit(0.4e18, alice);
        int256 beforeP = bookView.book().realizedHousePnlWad;
        vm.prank(keeper);
        liquidation.withdrawKeeperCredit(0.4e18, keeper);
        assertEq(token.balanceOf(keeper), 400_000);
        assertEq(bookView.book().fundedPayablesWad, 0.6e18);
        assertEq(liquidation.totalKeeperPayable(), 0);
        assertEq(bookView.book().realizedHousePnlWad, beforeP);
    }

    function test_QueueActiveLiquidationSucceedsWithNoBounty() public {
        bookView.seedEntitlement(2, 100e18);
        uint256 id = _openCash(1, alice, true);
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        assertEq(liquidation.keeperPayable(address(this)), 0);
        assertEq(bookView.book().fundedPayablesWad, 0);
        assertEq(bookView.book().sideBucketWad, 100e18);
        assertEq(queue.harvest(128), 100e18);
    }

    function test_FailedKeeperExitPreservesFundedPayable() public {
        uint256 id = _openCash(1, alice, true);
        _price(trading.tradeState(id).bustPrice1e18);
        liquidation.liquidate(1, id, new bytes[](0));
        token.configure(0, true, address(0), "");
        vm.expectRevert();
        liquidation.withdrawKeeperCredit(0.4e18, alice);
        assertEq(liquidation.keeperPayable(address(this)), 0.4e18);
        assertEq(liquidation.totalKeeperPayable(), 0.4e18);
        assertEq(bookView.book().fundedPayablesWad, 1e18);
    }
}
