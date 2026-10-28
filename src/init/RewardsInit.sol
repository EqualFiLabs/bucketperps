// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibRewards } from "../libraries/LibRewards.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { BackingVault } from "../rewards/BackingVault.sol";

import { BucketRewardToken } from "../rewards/BucketRewardToken.sol";

contract RewardsInit {
    error InvalidInitialization();

    function initialize(address staticsToken) external {
        LibRewards.State storage s = LibRewards.state();
        if (!LibProtocol.state().initializing || s.staticsToken != address(0)) {
            revert InvalidInitialization();
        }
        uint8 decimals = IERC20Metadata(staticsToken).decimals();
        s.staticsToken = staticsToken;
        s.backingVault = address(new BackingVault(staticsToken, address(this)));
        s.receipt = address(new BucketRewardToken(address(this), decimals));
    }
}
