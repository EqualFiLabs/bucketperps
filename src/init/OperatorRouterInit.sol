// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibFees } from "../libraries/LibFees.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";

contract OperatorRouterInit {
    error InvalidInitialization();

    function initialize(address router) external {
        if (
            !LibProtocol.state().initializing || LibFees.state().operatorRouter != address(0)
                || router.code.length == 0
        ) revert InvalidInitialization();
        LibFees.state().operatorRouter = router;
    }
}
