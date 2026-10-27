// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";

contract AccountsInit {
    error InvalidInitialization();

    function initialize(address positionNFT, address staticsDiamond) external {
        LibAccountsStorage.State storage s = LibAccountsStorage.state();
        if (
            !LibProtocol.state().initializing || s.positionNFT != address(0) || positionNFT.code.length == 0
                || staticsDiamond.code.length == 0
        ) revert InvalidInitialization();
        s.positionNFT = positionNFT;
        s.staticsDiamond = staticsDiamond;
    }
}
