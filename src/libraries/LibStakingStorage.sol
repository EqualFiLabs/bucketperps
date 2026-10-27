// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library LibStakingStorage {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.staking.v1");

    struct State {
        uint256 totalEffectiveWeight;
    }

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }
}
