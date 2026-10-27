// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library LibHouse {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.house.v1");

    struct State {
        // Development defaults: zero threshold, 100% primary share, Governor as primary receiver.
        uint256 thresholdWad;
        address primaryReceiver;
        address secondaryReceiver;
        uint16 secondaryBps;
    }

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }
}
