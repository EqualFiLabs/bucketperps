// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibPnl } from "./LibPnl.sol";

library LibMarkets {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.markets.v1");

    struct FeeTerms {
        uint16 winStakerBps;
        uint16 winProtocolBps;
        uint16 winOperatorBps;
        uint16 lossStakerBps;
        uint16 lossProtocolBps;
        uint16 lossOperatorBps;
        uint16 keeperLossBps;
        uint256 keeperMaxWad;
    }

    struct Terms {
        FeeTerms fees;
        LibPnl.Curve curve;
        uint64 liquidationBufferWad;
    }

    struct Risk {
        bool enabled;
        bool opensEnabled;
        uint32 maxLeverage;
        uint256 minMarginWad;
        uint256 maxMarginWad;
        uint256 minNotionalWad;
        uint256 maxNotionalWad;
        uint256 maxLongOiWad;
        uint256 maxShortOiWad;
        uint256 maxTotalOiWad;
    }

    struct Market {
        bytes32 streamId;
        uint64 currentTermsVersion;
        Risk risk;
        uint256 longOiWad;
        uint256 shortOiWad;
    }

    struct State {
        uint256 globalOiCapWad;
        uint256 globalOiWad;
        mapping(bytes32 marketId => Market market) markets;
        mapping(bytes32 marketId => mapping(uint64 version => Terms terms)) versions;
    }

    error InvalidMarket();
    error InvalidFeeTerms();
    error MarketClosed();
    error TermsChanged();
    error AdmissionLimit();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function validateTerms(Terms memory terms) internal pure {
        LibPnl.validateCurve(terms.curve);
        FeeTerms memory f = terms.fees;
        if (
            uint256(f.winStakerBps) + f.winProtocolBps + f.winOperatorBps > 10_000
                || uint256(f.lossStakerBps) + f.lossProtocolBps + f.lossOperatorBps > 10_000
                || terms.liquidationBufferWad >= 1e18
        ) revert InvalidFeeTerms();
    }

    function admit(bytes32 id, uint64 expectedVersion, uint256 margin, uint32 leverage, bool isLong)
        internal
        returns (uint256 notional)
    {
        State storage s = state();
        Market storage m = s.markets[id];
        Risk storage r = m.risk;
        if (!r.enabled || !r.opensEnabled || m.currentTermsVersion == 0) revert MarketClosed();
        if (m.currentTermsVersion != expectedVersion) revert TermsChanged();
        notional = margin * leverage;
        uint256 sideOi = isLong ? m.longOiWad : m.shortOiWad;
        uint256 sideCap = isLong ? r.maxLongOiWad : r.maxShortOiWad;
        if (
            leverage == 0 || leverage > r.maxLeverage || margin < r.minMarginWad || margin > r.maxMarginWad
                || notional < r.minNotionalWad || notional > r.maxNotionalWad || notional == 0
                || notional > LibPnl.MAX_NOTIONAL || sideOi + notional > sideCap
                || m.longOiWad + m.shortOiWad + notional > r.maxTotalOiWad
                || s.globalOiWad + notional > s.globalOiCapWad
        ) revert AdmissionLimit();
        if (isLong) m.longOiWad += notional;
        else m.shortOiWad += notional;
        s.globalOiWad += notional;
    }

    function release(bytes32 id, uint256 notional, bool isLong) internal {
        State storage s = state();
        Market storage m = s.markets[id];
        if (isLong) m.longOiWad -= notional;
        else m.shortOiWad -= notional;
        s.globalOiWad -= notional;
    }
}
