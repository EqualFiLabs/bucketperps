// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @notice Proposed external-account ABI; real Statics compatibility is not yet qualified.
/// @dev The called Diamond must derive module authority from msg.sender. No authority argument exists.
interface IStaticsAccountBridge {
    function attachExternalAccountLeg(uint256 positionId, bytes32 moduleType, bytes32 localAccountId) external;
    function detachExternalAccountLeg(uint256 positionId, bytes32 moduleType, bytes32 localAccountId) external;
    function accountMultiplierBps(uint256 positionId) external view returns (uint256);
}
