// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibOracle } from "../libraries/LibOracle.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";

contract OracleInit {
    error InvalidInitialization();

    function initialize(address oracle) external {
        if (
            !LibProtocol.state().initializing || LibOracle.state().executionOracle != address(0)
                || oracle.code.length == 0
        ) revert InvalidInitialization();
        LibOracle.state().executionOracle = oracle;
    }
}
