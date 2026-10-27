// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library LibBookStorage {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.book.v1");

    struct State {
        address settlementToken;
        uint256 cashQuantum;
        uint256 custodyWad;
        uint256 accountCashWad;
        uint256 lockedCashMarginWad;
        uint256 fundedPayablesWad;
        uint256 sideBucketWad;
        uint256 queuedDebtWad;
        uint256 committedDebtWad;
        int256 realizedHousePnlWad;
    }

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }
}
