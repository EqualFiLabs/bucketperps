// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

enum FundingSource {
    Cash,
    Claim
}

struct ClaimPortion {
    uint256 claimId;
    uint256 amountWad;
}

struct OpenParams {
    bytes32 marketId;
    bool isLong;
    FundingSource fundingSource;
    uint256 marginWad;
    uint32 leverage;
    uint64 expectedTermsVersion;
    uint256 deadline;
}
