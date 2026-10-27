// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IStaticsExecutionOracle } from "../interfaces/IStaticsExecutionOracle.sol";
import { LibPnl } from "./LibPnl.sol";

library LibOracle {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.oracle.v1");

    struct State {
        address executionOracle;
    }

    error OracleNotConfigured();
    error UnexpectedStream();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function verify(bytes32 marketId, bytes32 expectedStream, bytes[] calldata fullReports)
        internal
        returns (IStaticsExecutionOracle.ExecutionPrice memory result)
    {
        address target = state().executionOracle;
        if (target == address(0)) revert OracleNotConfigured();
        if (expectedStream == bytes32(0)) revert UnexpectedStream();
        result = IStaticsExecutionOracle(target).verifyExecutionPrice(marketId, fullReports);
        if (result.streamId != expectedStream) revert UnexpectedStream();
        LibPnl.validatePrice(result.price1e18);
    }
}
