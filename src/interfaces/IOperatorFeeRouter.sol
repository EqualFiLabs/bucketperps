// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @notice Contribution ABI pinned to EqualFiLabs/operator-fee-router 09250b7b30b2a6d8fbe7007ca11f2f6708f866ae.
interface IOperatorFeeRouter {
    function addRewards(address asset, uint256 amount) external;
}
