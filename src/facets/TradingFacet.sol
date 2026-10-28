// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { OpenParams, ClaimPortion } from "../types/TradingTypes.sol";
import { LibTrades } from "../libraries/LibTrades.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

import { LibControls } from "../libraries/LibControls.sol";

contract TradingFacet {
    function openPosition(
        uint256 positionId,
        OpenParams calldata params,
        ClaimPortion[] calldata claims,
        bytes[] calldata fullReports
    ) external returns (uint256 tradeId) {
        LibGuard.enter();
        LibControls.requireClear(LibControls.OPENS | LibControls.SETTLEMENT);
        tradeId = LibTrades.open(positionId, params, claims, fullReports);
        LibGuard.exit();
    }

    function tradeState(uint256 tradeId) external view returns (LibTrades.Trade memory) {
        return LibTrades.state().trades[tradeId];
    }
}
