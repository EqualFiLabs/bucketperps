// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibControls } from "../libraries/LibControls.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

import { LibOracle } from "../libraries/LibOracle.sol";
import { LibFees } from "../libraries/LibFees.sol";

contract ControlFacet {
    error ActionNotReady();
    error InvalidDependency();
    event SafetyActionScheduled(bytes32 indexed operation, uint256 readyAt);
    event SafetyActionCancelled(bytes32 indexed operation);
    event SafetyDelaysChanged(uint64 upgradeDelay, uint64 dependencyDelay);
    event OracleChanged(address indexed previousOracle, address indexed nextOracle);
    event OperatorRouterChanged(address indexed previousRouter, address indexed nextRouter);

    function safetyAction(bytes32 operation) external view returns (uint256) {
        return LibControls.state().pending[operation];
    }

    function safetyDelay() external view returns (uint64) {
        return LibControls.state().safetyDelay;
    }

    function setSafetyDelays(uint64 upgradeDelay, uint64 dependencyDelay) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibProtocol.state().upgradeDelay = upgradeDelay;
        LibControls.state().safetyDelay = dependencyDelay;
        emit SafetyDelaysChanged(upgradeDelay, dependencyDelay);
        LibGuard.exit();
    }

    /// @notice Records an exact payload hash; execution is limited to the typed setters below.
    function scheduleSafetyAction(bytes32 operation) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        uint256 readyAt = block.timestamp + LibControls.state().safetyDelay;
        LibControls.state().pending[operation] = readyAt;
        emit SafetyActionScheduled(operation, readyAt);
        LibGuard.exit();
    }

    function cancelSafetyAction(bytes32 operation) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        delete LibControls.state().pending[operation];
        emit SafetyActionCancelled(operation);
        LibGuard.exit();
    }

    function executeOracle(address nextOracle) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        _consume(keccak256(abi.encode("oracle", nextOracle)));
        if (nextOracle.code.length == 0) revert InvalidDependency();
        emit OracleChanged(LibOracle.state().executionOracle, nextOracle);
        LibOracle.state().executionOracle = nextOracle;
        LibGuard.exit();
    }

    function executeOperatorRouter(address nextRouter) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        _consume(keccak256(abi.encode("operator-router", nextRouter)));
        if (nextRouter.code.length == 0) revert InvalidDependency();
        emit OperatorRouterChanged(LibFees.state().operatorRouter, nextRouter);
        LibFees.state().operatorRouter = nextRouter;
        LibGuard.exit();
    }

    function _consume(bytes32 operation) internal {
        uint256 readyAt = LibControls.state().pending[operation];
        if (readyAt == 0 || block.timestamp < readyAt) revert ActionNotReady();
        delete LibControls.state().pending[operation];
    }

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
