// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @notice Contribution ABI pinned to EqualFiLabs/operator-fee-router f98a17780cb250ce28f446ab54eb078512fb2e0b.
interface IOperatorFeeRouter {
    function addRewards(address asset, uint256 amount) external;
}
