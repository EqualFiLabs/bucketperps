// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibUnits } from "../libraries/LibUnits.sol";

contract CashInit {
    error InvalidInitialization();

    function initialize(address settlementToken) external {
        LibBookStorage.State storage b = LibBookStorage.state();
        if (!LibProtocol.state().initializing || b.settlementToken != address(0)) {
            revert InvalidInitialization();
        }
        b.cashQuantum = LibUnits.tokenQuantum(settlementToken);
        b.settlementToken = settlementToken;
    }
}
