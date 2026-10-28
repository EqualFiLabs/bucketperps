// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { FundingSource, OpenParams, ClaimPortion } from "../types/TradingTypes.sol";
import { LibAccounts } from "./LibAccounts.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { LibPnl } from "./LibPnl.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibUnits } from "./LibUnits.sol";
import { LibQueue } from "./LibQueue.sol";
import { LibCash } from "./LibCash.sol";

library LibTrades {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.trades.v1");

    struct Trade {
        uint256 positionId;
        bytes32 marketId;
        bytes32 streamId;
        FundingSource fundingSource;
        bool isLong;
        uint256 marginWad;
        uint256 notionalWad;
        uint256 entryPrice1e18;
        uint256 bustPrice1e18;
        uint32 leverage;
        uint64 termsVersion;
        uint64 openedAt;
        bool settled;
    }

    struct State {
        uint256 nextTradeId;
        mapping(uint256 tradeId => Trade trade) trades;
        mapping(uint256 positionId => uint256[]) accountTradeIds;
    }

    error DeadlineExpired();
    error InvalidFunding();
    error InvalidTrade();
    error AlreadySettled();
    error TimestampOutOfRange();

    event TradeOpened(
        uint256 indexed tradeId,
        uint256 indexed positionId,
        bytes32 indexed marketId,
        FundingSource fundingSource,
        bool isLong,
        uint256 marginWad,
        uint256 notionalWad,
        uint256 entryPrice1e18,
        uint256 bustPrice1e18,
        uint64 termsVersion
    );

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function open(
        uint256 positionId,
        OpenParams calldata p,
        ClaimPortion[] calldata portions,
        bytes[] calldata reports
    ) internal returns (uint256 tradeId) {
        LibAccounts.requireOwner(positionId);
        LibCash.requireBacking();
        if (block.timestamp > p.deadline) revert DeadlineExpired();
        if (block.timestamp > type(uint64).max) revert TimestampOutOfRange();
        if (p.fundingSource == FundingSource.Cash && portions.length != 0) revert InvalidFunding();
        LibUnits.toTokenUnits(p.marginWad, LibBookStorage.state().cashQuantum);
        tradeId = ++state().nextTradeId;
        state().accountTradeIds[positionId].push(tradeId);
        Trade storage t = state().trades[tradeId];
        t.positionId = positionId;
        t.marketId = p.marketId;
        t.streamId = LibMarkets.state().markets[p.marketId].streamId;
        t.fundingSource = p.fundingSource;
        t.isLong = p.isLong;
        t.marginWad = p.marginWad;
        t.notionalWad =
            LibMarkets.admit(p.marketId, p.expectedTermsVersion, p.marginWad, p.leverage, p.isLong);
        t.leverage = p.leverage;
        t.termsVersion = p.expectedTermsVersion;
        t.openedAt = uint64(block.timestamp);
        if (p.fundingSource == FundingSource.Cash) _lockCash(positionId, p.marginWad);
        else LibQueue.consume(positionId, tradeId, p.marginWad, portions);
        _price(t, reports);
        ++LibAccountsStorage.state().accounts[positionId].openTradeCount;
        LibAccounts.syncActivity(positionId);
        _emitOpen(tradeId, t);
    }

    function _lockCash(uint256 positionId, uint256 margin) private {
        LibBookStorage.State storage b = LibBookStorage.state();
        LibAccountsStorage.state().accounts[positionId].cashWad -= margin;
        b.accountCashWad -= margin;
        b.lockedCashMarginWad += margin;
    }

    function _price(Trade storage t, bytes[] calldata reports) private {
        t.entryPrice1e18 = LibOracle.verify(t.marketId, t.streamId, reports).price1e18;
        t.bustPrice1e18 = LibPnl.bustPrice(
            t.entryPrice1e18,
            t.leverage,
            LibMarkets.state().versions[t.marketId][t.termsVersion].liquidationBufferWad,
            t.isLong
        );
    }

    function _emitOpen(uint256 tradeId, Trade storage t) private {
        emit TradeOpened(
            tradeId,
            t.positionId,
            t.marketId,
            t.fundingSource,
            t.isLong,
            t.marginWad,
            t.notionalWad,
            t.entryPrice1e18,
            t.bustPrice1e18,
            t.termsVersion
        );
    }

    function requireLive(uint256 positionId, uint256 tradeId) internal view returns (Trade storage t) {
        t = state().trades[tradeId];
        if (tradeId == 0 || t.positionId != positionId || t.marginWad == 0) revert InvalidTrade();
        if (t.settled) revert AlreadySettled();
    }

    /// @dev Used only by the atomic settlement path; does not itself resolve margin or entitlements.
    function retire(Trade storage t) internal {
        if (t.settled) revert AlreadySettled();
        t.settled = true;
        LibMarkets.release(t.marketId, t.notionalWad, t.isLong);
        --LibAccountsStorage.state().accounts[t.positionId].openTradeCount;
    }
}
