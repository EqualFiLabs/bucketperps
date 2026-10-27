// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

library LibAccountsStorage {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.accounts.v1");

    struct Account {
        uint256 cashWad;
        uint256 committedClaimMarginWad;
        uint256 unstakedRewardUnits;
        uint256 rawStakeUnits;
        uint256 effectiveWeight;
        uint256 revenueIndexPaid;
        uint256 claimableRevenueWad;
        uint256 openTradeCount;
        uint256 liveClaimCount;
        bool externalStateActive;
    }

    struct State {
        address positionNFT;
        address staticsDiamond;
        mapping(uint256 positionId => Account account) accounts;
    }

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }
}
