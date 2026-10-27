// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibFees } from "../libraries/LibFees.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibCash } from "../libraries/LibCash.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract FeeFacet {
    event ProtocolFeesWithdrawn(address indexed receiver, uint256 amountWad);

    function feePayables() external view returns (LibFees.State memory) {
        return LibFees.state();
    }

    function withdrawProtocolFees(uint256 amountWad, address receiver) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibFees.state().protocolPayableWad -= amountWad;
        LibBookStorage.state().fundedPayablesWad -= amountWad;
        LibCash.sendExact(receiver, amountWad);
        emit ProtocolFeesWithdrawn(receiver, amountWad);
        LibGuard.exit();
    }
}
