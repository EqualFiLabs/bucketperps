// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Allocated STATICS custody. Only the fixed BucketPerps controller can release backing.
contract BackingVault {
    using SafeERC20 for IERC20;
    IERC20 public immutable asset;
    address public immutable controller;

    error Unauthorized();
    error InexactTransfer();

    constructor(address asset_, address controller_) {
        asset = IERC20(asset_);
        controller = controller_;
    }

    function release(address receiver, uint256 units) external {
        if (msg.sender != controller) revert Unauthorized();
        uint256 beforeVault = asset.balanceOf(address(this));
        uint256 beforeReceiver = asset.balanceOf(receiver);
        asset.safeTransfer(receiver, units);
        if (
            asset.balanceOf(address(this)) + units != beforeVault
                || asset.balanceOf(receiver) != beforeReceiver + units
        ) {
            revert InexactTransfer();
        }
    }
}
