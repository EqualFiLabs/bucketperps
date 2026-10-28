// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibRewards } from "../libraries/LibRewards.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract RewardFacet {
    event RewardInventoryFunded(address indexed funder, uint256 units);

    function rewardState() external view returns (LibRewards.State memory) {
        return LibRewards.state();
    }

    function fundRewardInventory(uint256 units) external {
        LibGuard.enter();
        if (units == 0) revert LibRewards.InvalidAmount();
        LibRewards.transferExact(msg.sender, address(this), units);
        LibRewards.state().inventoryUnits += units;
        emit RewardInventoryFunded(msg.sender, units);
        LibGuard.exit();
    }
}
