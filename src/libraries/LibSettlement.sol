// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibBook } from "./LibBook.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { LibAccounts } from "./LibAccounts.sol";
import { LibQueue } from "./LibQueue.sol";
import { LibUnits } from "./LibUnits.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FundingSource } from "../types/TradingTypes.sol";
import { LibTrades } from "./LibTrades.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { LibPnl } from "./LibPnl.sol";
import { LibFees } from "./LibFees.sol";
import { LibCash } from "./LibCash.sol";

import { LibRewards } from "./LibRewards.sol";

import { LibControls } from "./LibControls.sol";

library LibSettlement {
    using SafeCast for uint256;

    struct Result {
        uint256 exitPrice1e18;
        int256 rawPnlWad;
        uint256 profitWad;
        uint256 lossWad;
        uint256 netProfitWad;
        uint256 principalWad;
        uint256 quotedFeeWad;
        uint256 fundedFeeWad;
        uint256 fundedProtocolWad;
        bool busted;
        Payout entitlement;
    }

    error NotBusted();
    event TradeSettled(uint256 indexed tradeId, uint256 indexed positionId, Result result);

    struct Payout {
        uint256 paidWad;
        uint256 queuedWad;
        uint256 claimId;
    }

    function settle(uint256 positionId, uint256 tradeId, bytes[] calldata reports, bool requireBust)
        internal
        returns (Result memory r)
    {
        LibControls.requireClear(LibControls.SETTLEMENT);
        LibTrades.Trade storage t = LibTrades.requireLive(positionId, tradeId);
        LibCash.requireBacking();
        r.exitPrice1e18 =
        LibOracle.verify(t.marketId, LibMarkets.state().markets[t.marketId].streamId, reports).price1e18;
        r.busted = LibPnl.isBusted(r.exitPrice1e18, t.bustPrice1e18, t.isLong);
        if (requireBust && !r.busted) revert NotBusted();
        _outcome(t, r);
        LibTrades.retire(t);
        _principal(t, r);
        LibMarkets.FeeTerms memory f = LibMarkets.state().versions[t.marketId][t.termsVersion].fees;
        LibFees.Quote memory q;
        if (r.profitWad != 0) {
            q = LibFees.quote(r.profitWad, f, true);
            r.netProfitWad = r.profitWad - q.totalWad;
        } else if (r.lossWad != 0 && !(r.busted && t.fundingSource == FundingSource.Claim)) {
            q = LibFees.quote(r.lossWad, f, false);
        }
        r.quotedFeeWad = q.totalWad;
        uint256 entitlement = r.netProfitWad;
        if (t.fundingSource == FundingSource.Claim) entitlement += t.marginWad - r.lossWad;
        r.entitlement = payout(positionId, entitlement);
        (r.fundedFeeWad, r.fundedProtocolWad) = LibFees.fund(q);
        LibBookStorage.state().realizedHousePnlWad += r.lossWad.toInt256() - r.netProfitWad.toInt256()
        - r.fundedFeeWad.toInt256();
        LibRewards.rewardLoss(positionId, tradeId, r.lossWad);
        LibAccounts.syncActivity(positionId);
        emit TradeSettled(tradeId, positionId, r);
    }

    function _outcome(LibTrades.Trade storage t, Result memory r) private view {
        if (r.busted) {
            r.lossWad = t.marginWad;
            r.rawPnlWad = -t.marginWad.toInt256();
            return;
        }
        int256 adjusted;
        (r.rawPnlWad, adjusted) = LibPnl.calculate(
            LibPnl.Position(t.entryPrice1e18, r.exitPrice1e18, t.marginWad, t.leverage, t.isLong),
            LibMarkets.state().versions[t.marketId][t.termsVersion].curve
        );
        uint256 quantum = LibBookStorage.state().cashQuantum;
        if (adjusted > 0) r.profitWad = LibUnits.floorCash(uint256(adjusted), quantum);
        else r.lossWad = LibUnits.floorCash(uint256(-adjusted), quantum);
    }

    function _principal(LibTrades.Trade storage t, Result memory r) private {
        LibBookStorage.State storage b = LibBookStorage.state();
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[t.positionId];
        if (t.fundingSource == FundingSource.Cash) {
            b.lockedCashMarginWad -= t.marginWad;
            r.principalWad = t.marginWad - r.lossWad;
            a.cashWad += r.principalWad;
            b.accountCashWad += r.principalWad;
            if (b.queuedDebtWad != 0) b.sideBucketWad += r.lossWad;
        } else {
            b.committedDebtWad -= t.marginWad;
            a.committedClaimMarginWad -= t.marginWad;
        }
    }

    /// @dev Cash principal is handled separately. This only changes funding/debt timing, not PnL.
    function payout(uint256 positionId, uint256 entitlement) internal returns (Payout memory result) {
        if (entitlement == 0) return result;
        LibUnits.toTokenUnits(entitlement, LibBookStorage.state().cashQuantum);
        uint256 budget = LibBook.directBudget();
        result.paidWad = entitlement < budget ? entitlement : budget;
        if (result.paidWad != 0) {
            LibAccountsStorage.state().accounts[positionId].cashWad += result.paidWad;
            LibBookStorage.state().accountCashWad += result.paidWad;
        }
        result.queuedWad = entitlement - result.paidWad;
        if (result.queuedWad != 0) result.claimId = LibQueue.enqueue(positionId, result.queuedWad);
        LibAccounts.syncActivity(positionId);
    }
}
