// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { LibStaking } from "../libraries/LibStaking.sol";
import { LibStakingStorage } from "../libraries/LibStakingStorage.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibFees } from "../libraries/LibFees.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

import { IStaticsAccountBridge } from "../interfaces/IStaticsAccountBridge.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { LibControls } from "../libraries/LibControls.sol";

contract StakingFacet {
    error InvalidWeightCallback();
    event CanonicalWeightChanged(
        uint256 indexed positionId, uint256 previousMultiplierBps, uint256 nextMultiplierBps
    );

    /// @notice Called atomically by the Statics Diamond on every canonical multiplier transition.
    function onAccountMultiplierChanged(uint256 id, uint256 previousBps, uint256 nextBps) external {
        LibGuard.enter();
        if (msg.sender != LibAccountsStorage.state().staticsDiamond) revert InvalidWeightCallback();
        LibStakingStorage.State storage s = LibStakingStorage.state();
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        if (a.rawStakeUnits != 0 && s.multiplierBps[id] != previousBps) revert InvalidWeightCallback();
        LibStaking.checkpoint(id);
        _setWeight(id, nextBps);
        emit CanonicalWeightChanged(id, previousBps, nextBps);
        LibGuard.exit();
    }

    event StakeChanged(uint256 indexed positionId, uint256 rawStakeUnits, uint256 effectiveWeight);
    event StakerRevenueClaimed(uint256 indexed positionId, uint256 amountWad);

    function stake(uint256 id, uint256 units) external {
        LibGuard.enter();
        LibControls.requireClear(LibControls.STAKING);
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
        LibControls.requireClear(LibControls.STAKING);
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
        LibControls.requireClear(LibControls.WITHDRAWALS);
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
        uint256 multiplier =
            IStaticsAccountBridge(LibAccountsStorage.state().staticsDiamond).accountMultiplierBps(id);
        _setWeight(id, multiplier);
    }

    function _setWeight(uint256 id, uint256 multiplier) internal {
        LibStakingStorage.State storage s = LibStakingStorage.state();
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        uint256 next = Math.mulDiv(a.rawStakeUnits, multiplier, 10_000);
        s.totalEffectiveWeight = s.totalEffectiveWeight - a.effectiveWeight + next;
        a.effectiveWeight = next;
        s.multiplierBps[id] = multiplier;
        emit StakeChanged(id, a.rawStakeUnits, next);
    }
}
