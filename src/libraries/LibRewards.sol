// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library LibRewards {
    using SafeERC20 for IERC20;
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.rewards.v1");

    struct State {
        address staticsToken;
        address backingVault;
        address receipt;
        uint256 inventoryUnits;
        uint256 allocatedUnits;
        uint256 wrapCapacityUnits;
        uint256 rewardUnitsPerDollar;
        bool wrappingEnabled;
        bool unwrappingEnabled;
    }

    error InvalidAmount();
    error InexactTransfer();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function transferExact(address from, address to, uint256 units) internal {
        IERC20 token = IERC20(state().staticsToken);
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        if (from == address(this)) token.safeTransfer(to, units);
        else token.safeTransferFrom(from, to, units);
        if (token.balanceOf(from) + units != beforeFrom || token.balanceOf(to) != beforeTo + units) {
            revert InexactTransfer();
        }
    }
}
