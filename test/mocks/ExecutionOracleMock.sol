// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";

/// @dev Transport fixture. No signature, Chainlink billing or production sequencer qualification.
contract ExecutionOracleMock {
    IStaticsExecutionOracle.ExecutionPrice internal response;
    bytes public failure;
    address public lastConsumer;
    bytes32 public lastMarket;
    bytes32 public lastBundleHash;
    uint256 public calls;
    address public callback;
    bytes public callbackData;

    function setResponse(IStaticsExecutionOracle.ExecutionPrice calldata value) external {
        response = value;
    }

    function setFailure(bytes calldata reason) external {
        failure = reason;
    }

    function setCallback(address target, bytes calldata data) external {
        callback = target;
        callbackData = data;
    }

    function verifyExecutionPrice(bytes32 marketId, bytes[] calldata reports)
        external
        returns (IStaticsExecutionOracle.ExecutionPrice memory)
    {
        bytes memory reason = failure;
        if (reason.length != 0) {
            assembly { revert(add(reason, 32), mload(reason)) }
        }
        lastConsumer = msg.sender;
        lastMarket = marketId;
        lastBundleHash = keccak256(abi.encode(reports));
        ++calls;
        if (callback != address(0)) {
            (bool ok, bytes memory result) = callback.call(callbackData);
            if (!ok) {
                assembly { revert(add(result, 32), mload(result)) }
            }
        }
        return response;
    }
}
