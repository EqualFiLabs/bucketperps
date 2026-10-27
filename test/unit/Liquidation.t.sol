// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibSettlement } from "../../src/libraries/LibSettlement.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";

contract LiquidationTest is ProtocolFixture {
    function test_StreamRotationPreservesLiquidationOfExistingPosition() public {
        uint256 id = _openCash(1, alice, true);
        uint256 boundary = trading.tradeState(id).bustPrice1e18;
        bytes32 replacement = keccak256("replacement fixture stream");
        markets.configureMarket(MARKET, replacement, _risk());
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(boundary, 100, 99, 101, replacement));
        LibSettlement.Result memory r = liquidation.liquidate(1, id, new bytes[](0));
        assertTrue(r.busted);
        assertEq(r.lossWad, 100e18);
        assertEq(bookView.book().lockedCashMarginWad, 0);
        assertEq(accounts.accountState(1).openTradeCount, 0);
    }

    function test_OwnerCloseAndPublicLiquidationShareForfeitureAndBook() public {
        uint256 id = _openCash(1, alice, true);
        _price(trading.tradeState(id).bustPrice1e18);
        uint256 snapshot = vm.snapshotState();
        vm.prank(alice);
        LibSettlement.Result memory closed = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        LibBookStorage.State memory ownerBook = bookView.book();
        assertTrue(vm.revertToState(snapshot));
        vm.prank(makeAddr("keeper"));
        LibSettlement.Result memory liquidated = liquidation.liquidate(1, id, new bytes[](0));
        assertEq(abi.encode(closed), abi.encode(liquidated));
        assertEq(abi.encode(ownerBook), abi.encode(bookView.book()));
        assertEq(closed.lossWad, 100e18);
        assertEq(accounts.accountState(1).cashWad, 900e18);
        assertEq(accounts.accountState(1).openTradeCount, 0);
        vm.expectRevert(LibTrades.AlreadySettled.selector);
        liquidation.liquidate(1, id, new bytes[](0));
    }

    function test_LongAndShortBoundaryIsInclusiveAndInsideCannotLiquidate() public {
        for (uint256 side; side < 2; ++side) {
            bool isLong = side == 0;
            _price(50_000e18);
            uint256 id = _openCash(1, alice, isLong);
            uint256 boundary = trading.tradeState(id).bustPrice1e18;
            _price(isLong ? boundary + 1 : boundary - 1);
            vm.expectRevert(LibSettlement.NotBusted.selector);
            liquidation.liquidate(1, id, new bytes[](0));
            assertFalse(trading.tradeState(id).settled);
            _price(boundary);
            LibSettlement.Result memory r = liquidation.liquidate(1, id, new bytes[](0));
            assertEq(r.lossWad, 100e18);
            assertTrue(r.busted);
        }
        (uint256 oi,) = markets.globalOpenInterest();
        assertEq(oi, 0);
    }

    function test_ClaimLiquidationCancelsDebtWithNoFeeOrCashGain() public {
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        uint256 id = _openClaim(1, alice, claimId);
        _price(trading.tradeState(id).bustPrice1e18);
        LibSettlement.Result memory r = liquidation.liquidate(1, id, new bytes[](0));
        assertEq(r.quotedFeeWad, 0);
        assertEq(r.fundedFeeWad, 0);
        assertEq(bookView.book().committedDebtWad, 0);
        assertEq(bookView.book().fundedPayablesWad, 0);
        assertEq(bookView.book().custodyWad, 2_000e18);
        assertEq(bookView.book().accountCashWad, 2_000e18);
    }

    function test_WrongAccountAndFailedOracleCannotResolveTrade() public {
        uint256 id = _openCash(1, alice, true);
        vm.expectRevert(LibTrades.InvalidTrade.selector);
        liquidation.liquidate(2, id, new bytes[](0));
        oracle.setFailure(hex"deadbeef");
        vm.expectRevert(bytes4(0xdeadbeef));
        liquidation.liquidate(1, id, new bytes[](0));
        assertFalse(trading.tradeState(id).settled);
        assertEq(bookView.book().lockedCashMarginWad, 100e18);
        assertEq(accounts.accountState(1).openTradeCount, 1);
    }
}
