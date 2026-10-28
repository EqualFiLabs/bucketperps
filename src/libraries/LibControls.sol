// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library LibControls {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.controls.v1");
    uint256 internal constant OPENS = 1;
    uint256 internal constant SETTLEMENT = 2;
    uint256 internal constant WITHDRAWALS = 4;
    uint256 internal constant QUEUE = 8;
    uint256 internal constant STAKING = 16;
    uint256 internal constant REWARDS = 32;
    uint256 internal constant FEES = 64;
    uint256 internal constant CONVERSION = 128;
    uint256 internal constant DEPOSITS = 256;
    uint256 internal constant SURPLUS = 512;

    struct State {
        uint256 pausedGroups;
        uint64 safetyDelay;
        mapping(bytes32 operation => uint256 readyAt) pending;
    }
    error OperationPaused(uint256 groups);

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function requireClear(uint256 groups) internal view {
        if (state().pausedGroups & groups != 0) revert OperationPaused(groups);
    }
}
