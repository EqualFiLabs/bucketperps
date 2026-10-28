// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibRewards } from "../libraries/LibRewards.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { BucketRewardToken } from "../rewards/BucketRewardToken.sol";
import { BackingVault } from "../rewards/BackingVault.sol";

import { LibProtocol } from "../libraries/LibProtocol.sol";

import { LibControls } from "../libraries/LibControls.sol";

contract RewardFacet {
    event LossRewardRateChanged(uint256 previousUnitsPerDollar, uint256 nextUnitsPerDollar);

    function setLossRewardRate(uint256 unitsPerDollar) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        uint256 previous = LibRewards.state().rewardUnitsPerDollar;
        LibRewards.state().rewardUnitsPerDollar = unitsPerDollar;
        emit LossRewardRateChanged(previous, unitsPerDollar);
        LibGuard.exit();
    }
    error ConversionDisabled();
    error InvalidReceiver();
    event Wrapped(uint256 indexed positionId, uint256 units);
    event Unwrapped(uint256 indexed positionId, address indexed receiver, uint256 units);

    function wrap(uint256 positionId, uint256 units) external {
        LibGuard.enter();
        LibControls.requireClear(LibControls.CONVERSION);
        LibAccounts.requireOwner(positionId);
        LibRewards.State storage s = LibRewards.state();
        if (!s.wrappingEnabled) revert ConversionDisabled();
        if (units == 0) revert LibRewards.InvalidAmount();
        s.wrapCapacityUnits -= units;
        s.allocatedUnits += units;
        LibAccountsStorage.state().accounts[positionId].unstakedRewardUnits += units;
        LibRewards.transferExact(msg.sender, s.backingVault, units);
        BucketRewardToken(s.receipt).mint(units);
        LibAccounts.syncActivity(positionId);
        emit Wrapped(positionId, units);
        LibGuard.exit();
    }

    function unwrap(uint256 positionId, uint256 units, address receiver) external {
        LibGuard.enter();
        LibControls.requireClear(LibControls.CONVERSION);
        LibAccounts.requireOwner(positionId);
        LibRewards.State storage s = LibRewards.state();
        if (!s.unwrappingEnabled) revert ConversionDisabled();
        if (units == 0) revert LibRewards.InvalidAmount();
        if (receiver == address(0) || receiver == address(this) || receiver == s.backingVault) {
            revert InvalidReceiver();
        }
        LibAccountsStorage.state().accounts[positionId].unstakedRewardUnits -= units;
        s.allocatedUnits -= units;
        if (s.wrappingEnabled) s.wrapCapacityUnits += units;
        BucketRewardToken(s.receipt).burn(units);
        BackingVault(s.backingVault).release(receiver, units);
        LibAccounts.syncActivity(positionId);
        emit Unwrapped(positionId, receiver, units);
        LibGuard.exit();
    }

    event RewardInventoryFunded(address indexed funder, uint256 units);

    function rewardState() external view returns (LibRewards.State memory) {
        return LibRewards.state();
    }

    function fundRewardInventory(uint256 units) external {
        LibGuard.enter();
        LibControls.requireClear(LibControls.DEPOSITS);
        if (units == 0) revert LibRewards.InvalidAmount();
        LibRewards.transferExact(msg.sender, address(this), units);
        LibRewards.state().inventoryUnits += units;
        emit RewardInventoryFunded(msg.sender, units);
        LibGuard.exit();
    }
}
