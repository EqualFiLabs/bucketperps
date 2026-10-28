// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { LibStaking } from "../libraries/LibStaking.sol";
import { LibStakingStorage } from "../libraries/LibStakingStorage.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibFees } from "../libraries/LibFees.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract StakingFacet {
    event StakeChanged(uint256 indexed positionId, uint256 rawStakeUnits, uint256 effectiveWeight);
    event StakerRevenueClaimed(uint256 indexed positionId, uint256 amountWad);

    function stake(uint256 id, uint256 units) external {
        LibGuard.enter();
        LibAccounts.requireOwner(id);
        LibStaking.checkpoint(id);
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        a.unstakedRewardUnits -= units;
        a.rawStakeUnits += units;
        LibStakingStorage.state().totalRawStakeUnits += units;
        _weight(id);
        LibAccounts.syncActivity(id);
        LibGuard.exit();
    }

    function unstake(uint256 id, uint256 units) external {
        LibGuard.enter();
        LibAccounts.requireOwner(id);
        LibStaking.checkpoint(id);
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        a.rawStakeUnits -= units;
        a.unstakedRewardUnits += units;
        LibStakingStorage.state().totalRawStakeUnits -= units;
        _weight(id);
        LibAccounts.syncActivity(id);
        LibGuard.exit();
    }

    function claimStakerRevenue(uint256 id) external returns (uint256 amountWad) {
        LibGuard.enter();
        LibAccounts.requireOwner(id);
        LibStaking.checkpoint(id);
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        amountWad = a.claimableRevenueWad;
        a.claimableRevenueWad = 0;
        a.cashWad += amountWad;
        LibFees.state().stakerPayableWad -= amountWad;
        LibBookStorage.state().fundedPayablesWad -= amountWad;
        LibBookStorage.state().accountCashWad += amountWad;
        LibAccounts.syncActivity(id);
        emit StakerRevenueClaimed(id, amountWad);
        LibGuard.exit();
    }

    function pendingStakerRevenue(uint256 id) external view returns (uint256) {
        (uint256 earned,) = LibStaking.accrued(id);
        return LibAccountsStorage.state().accounts[id].claimableRevenueWad + earned;
    }

    function stakingTotals()
        external
        view
        returns (uint256 rawStake, uint256 weight, uint256 index, uint256 roundingScaled)
    {
        LibStakingStorage.State storage s = LibStakingStorage.state();
        return (s.totalRawStakeUnits, s.totalEffectiveWeight, s.revenueIndex, s.unindexedRevenueScaled);
    }

    function _weight(uint256 id) internal {
        LibStakingStorage.State storage s = LibStakingStorage.state();
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        s.totalEffectiveWeight = s.totalEffectiveWeight - a.effectiveWeight + a.rawStakeUnits;
        a.effectiveWeight = a.rawStakeUnits;
        emit StakeChanged(id, a.rawStakeUnits, a.effectiveWeight);
    }
}
