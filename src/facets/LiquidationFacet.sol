// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibSettlement } from "../libraries/LibSettlement.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract LiquidationFacet {
    event LiquidationExecuted(
        uint256 indexed tradeId,
        uint256 indexed positionId,
        address indexed keeper,
        uint256 forfeitedMarginWad
    );

    function liquidate(uint256 positionId, uint256 tradeId, bytes[] calldata fullReports)
        external
        returns (LibSettlement.Result memory result)
    {
        LibGuard.enter();
        result = LibSettlement.settle(positionId, tradeId, fullReports, true);
        emit LiquidationExecuted(tradeId, positionId, msg.sender, result.lossWad);
        LibGuard.exit();
    }
}
