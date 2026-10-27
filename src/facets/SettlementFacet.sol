// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibSettlement } from "../libraries/LibSettlement.sol";
import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibTrades } from "../libraries/LibTrades.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract SettlementFacet {
    function closePosition(
        uint256 positionId,
        uint256 tradeId,
        uint256 deadline,
        bytes[] calldata fullReports
    ) external returns (LibSettlement.Result memory result) {
        LibGuard.enter();
        LibAccounts.requireOwner(positionId);
        if (block.timestamp > deadline) revert LibTrades.DeadlineExpired();
        result = LibSettlement.settle(positionId, tradeId, fullReports, false);
        LibGuard.exit();
    }
}
