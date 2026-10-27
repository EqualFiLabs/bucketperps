// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @dev All state-changing entry points share this lock across delegatecalls.
library LibGuard {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.reentrancy.v1");

    struct State {
        bool entered;
    }

    error ReentrantCall();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }

    function enter() internal {
        State storage s = state();
        if (s.entered) revert ReentrantCall();
        s.entered = true;
    }

    function exit() internal {
        state().entered = false;
    }
}
