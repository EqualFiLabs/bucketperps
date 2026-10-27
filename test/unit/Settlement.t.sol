// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { LibSettlement } from "../../src/libraries/LibSettlement.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibOracle } from "../../src/libraries/LibOracle.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";

contract SettlementTest is ProtocolFixture {
    function test_StreamRotationSettlesExistingAndNewTradesWithoutChangingOpeningTerms() public {
        uint256 oldId = _openCash(1, alice, true);
        LibTrades.Trade memory oldTrade = trading.tradeState(oldId);
        bytes32 replacement = keccak256("replacement fixture stream");
        markets.configureMarket(MARKET, replacement, _risk());
        vm.prank(alice);
        vm.expectRevert(LibOracle.UnexpectedStream.selector);
        settlement.closePosition(1, oldId, block.timestamp, new bytes[](0));
        assertFalse(trading.tradeState(oldId).settled);
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(50_000e18, 100, 99, 101, replacement));
        uint256 newId = _openCash(2, bob, false);
        vm.prank(alice);
        settlement.closePosition(1, oldId, block.timestamp, new bytes[](0));
        vm.prank(bob);
        settlement.closePosition(2, newId, block.timestamp, new bytes[](0));
        assertEq(trading.tradeState(oldId).streamId, STREAM);
        assertEq(trading.tradeState(newId).streamId, replacement);
        assertEq(trading.tradeState(oldId).entryPrice1e18, oldTrade.entryPrice1e18);
        assertEq(trading.tradeState(oldId).bustPrice1e18, oldTrade.bustPrice1e18);
        assertEq(trading.tradeState(oldId).termsVersion, oldTrade.termsVersion);
        assertEq(accounts.accountState(1).cashWad, 1_000e18);
        assertEq(accounts.accountState(2).cashWad, 1_000e18);
        (uint256 oi,) = markets.globalOpenInterest();
        assertEq(oi, 0);
    }

    function test_CashWinnerReturnsPrincipalAndQueuesOnlyNetProfit() public {
        uint256 id = _openCash(1, alice, true);
        _price(50_500e18);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.principalWad, 100e18);
        assertGt(r.profitWad, 0);
        assertEq(r.netProfitWad, r.profitWad - r.quotedFeeWad);
        assertEq(r.entitlement.queuedWad, r.netProfitWad);
        assertEq(r.entitlement.paidWad, 0);
        assertEq(accounts.accountState(1).cashWad, 1_000e18);
        assertEq(bookView.book().realizedHousePnlWad, -int256(r.netProfitWad));
        assertEq(bookView.book().fundedPayablesWad, 0);
        assertEq(bookView.book().lockedCashMarginWad, 0);
        vm.prank(alice);
        vm.expectRevert(LibTrades.AlreadySettled.selector);
        settlement.closePosition(1, id, block.timestamp, new bytes[](0));
    }

    function test_CashLossAndActiveQueueWaiverUseActualLostCash() public {
        uint256 old = bookView.seedEntitlement(2, 100e18);
        uint256 id = _openCash(1, alice, true);
        _price(49_900e18); // $20 pre-bust loss at 100x.
        int256 beforeP = bookView.book().realizedHousePnlWad;
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.lossWad, 20e18);
        assertEq(r.principalWad, 80e18);
        assertEq(r.fundedFeeWad, 0);
        assertEq(bookView.book().sideBucketWad, 20e18);
        assertEq(bookView.book().realizedHousePnlWad, beforeP + 20e18);
        assertEq(queue.harvest(128), 20e18);
        assertEq(queue.claimState(old).remainingWad, 80e18);
        assertEq(bookView.book().realizedHousePnlWad, beforeP + 20e18);
    }

    function test_CashFlatReturnsAllPrincipalWithoutFee() public {
        uint256 id = _openCash(1, alice, false);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.principalWad, 100e18);
        assertEq(accounts.accountState(1).cashWad, 1_000e18);
        assertEq(r.quotedFeeWad, 0);
        assertEq(bookView.book().realizedHousePnlWad, 0);
    }

    function test_ClaimLossCancelsDebtAndRequeuesOnlySurvivor() public {
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        uint256 id = _openClaim(1, alice, claimId);
        _price(49_900e18);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.lossWad, 20e18);
        assertEq(r.entitlement.queuedWad, 80e18);
        assertGt(r.entitlement.claimId, claimId);
        assertEq(bookView.book().committedDebtWad, 0);
        assertEq(bookView.book().queuedDebtWad, 80e18);
        assertEq(bookView.book().custodyWad, 2_000e18);
        assertEq(bookView.book().accountCashWad, 2_000e18);
        assertEq(bookView.book().realizedHousePnlWad, -80e18);
        assertEq(r.fundedFeeWad, 0);
    }

    function test_ClaimWinQueuesSurvivingPrincipalPlusNetProfitOnce() public {
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        uint256 id = _openClaim(1, alice, claimId);
        _price(50_500e18);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertEq(r.entitlement.queuedWad, 100e18 + r.netProfitWad);
        assertEq(bookView.book().realizedHousePnlWad, -100e18 - int256(r.netProfitWad));
        assertEq(accounts.accountState(1).committedClaimMarginWad, 0);
        assertEq(accounts.accountState(1).liveClaimCount, 1);
        assertEq(accounts.accountState(1).cashWad, 1_000e18);
    }

    function test_ClaimBustCancelsCommittedDebtWithoutCashOrFee() public {
        uint256 claimId = bookView.seedEntitlement(1, 100e18);
        uint256 id = _openClaim(1, alice, claimId);
        _price(trading.tradeState(id).bustPrice1e18);
        vm.prank(alice);
        LibSettlement.Result memory r = settlement.closePosition(1, id, block.timestamp, new bytes[](0));
        assertTrue(r.busted);
        assertEq(r.lossWad, 100e18);
        assertEq(r.quotedFeeWad, 0);
        assertEq(bookView.book().committedDebtWad, 0);
        assertEq(bookView.book().queuedDebtWad, 0);
        assertEq(bookView.book().fundedPayablesWad, 0);
        assertEq(bookView.book().realizedHousePnlWad, 0);
        assertEq(bookView.book().custodyWad, 2_000e18);
    }

    function test_RealBookReconcilesAfterOpposingTradesWithFundedLossFees() public {
        uint256 longId = _openCash(1, alice, true);
        uint256 shortId = _openCash(2, bob, false);
        _price(49_900e18);
        vm.prank(alice);
        LibSettlement.Result memory loss =
            settlement.closePosition(1, longId, block.timestamp, new bytes[](0));
        assertEq(loss.lossWad, 20e18);
        assertEq(loss.quotedFeeWad, 0.4e18);
        assertEq(loss.fundedFeeWad, 0.2e18); // No stake: retain its $0.20 slice.
        vm.prank(bob);
        settlement.closePosition(2, shortId, block.timestamp, new bytes[](0));
        LibBookStorage.State memory b = bookView.book();
        uint256 house = b.custodyWad - b.accountCashWad - b.lockedCashMarginWad - b.fundedPayablesWad;
        assertEq(int256(house) - int256(b.queuedDebtWad) - int256(b.committedDebtWad), b.realizedHousePnlWad);
        assertEq(b.accountCashWad, accounts.accountState(1).cashWad + accounts.accountState(2).cashWad);
        (uint256 oi,) = markets.globalOpenInterest();
        assertEq(oi, 0);
        assertEq(token.balanceOf(address(diamond)) * 1e12, b.custodyWad);
    }
}
