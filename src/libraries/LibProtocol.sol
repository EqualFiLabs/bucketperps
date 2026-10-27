// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library LibProtocol {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.protocol.v1");

    struct State {
        address governor;
        address guardian;
        uint64 upgradeDelay;
        bool initialized;
        bool finalized;
        bool initializing;
        mapping(bytes32 operation => uint256 readyAt) pendingCuts;
        mapping(address initializer => bool used) usedInitializers;
    }

    error Unauthorized();
    error AlreadyInitialized();
    error ProtocolFinalized();
    error InvalidAuthority();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }

    function requireGovernor() internal view {
        if (msg.sender != state().governor) revert Unauthorized();
    }

    function requireUpgradeable() internal view {
        if (state().finalized) revert ProtocolFinalized();
    }

    function initialize(address governor, address guardian, uint64 upgradeDelay) internal {
        State storage s = state();
        if (s.initialized) revert AlreadyInitialized();
        if (governor == address(0) || guardian == address(0)) revert InvalidAuthority();
        s.initialized = true;
        s.governor = governor;
        s.guardian = guardian;
        s.upgradeDelay = upgradeDelay;
    }
}
