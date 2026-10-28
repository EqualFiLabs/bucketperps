// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibControls } from "../libraries/LibControls.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract ControlFacet {
    event PauseChanged(uint256 pausedGroups);

    function pausedGroups() external view returns (uint256) {
        return LibControls.state().pausedGroups;
    }

    function pause(uint256 groups) external {
        LibGuard.enter();
        LibProtocol.State storage p = LibProtocol.state();
        if (msg.sender != p.guardian && msg.sender != p.governor) revert LibProtocol.Unauthorized();
        LibControls.state().pausedGroups |= groups;
        emit PauseChanged(LibControls.state().pausedGroups);
        LibGuard.exit();
    }

    function unpause(uint256 groups) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibControls.state().pausedGroups &= ~groups;
        emit PauseChanged(LibControls.state().pausedGroups);
        LibGuard.exit();
    }
}
