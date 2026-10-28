// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { LibStakingStorage } from "./LibStakingStorage.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibUnits } from "./LibUnits.sol";

library LibStaking {
    uint256 internal constant SCALE = 1e27;
    event StakerRevenueIndexed(uint256 amountWad, uint256 effectiveWeight, uint256 index);

    /// @dev Called only for funded fees with a positive denominator. Global index dust stays funded,
    /// but is never rolled into a later denominator or captured by a newly entering staker.
    function distribute(uint256 amountWad) internal {
        if (amountWad == 0) return;
        LibStakingStorage.State storage s = LibStakingStorage.state();
        s.revenueIndex += Math.mulDiv(amountWad, SCALE, s.totalEffectiveWeight);
        s.unindexedRevenueScaled += mulmod(amountWad, SCALE, s.totalEffectiveWeight);
        emit StakerRevenueIndexed(amountWad, s.totalEffectiveWeight, s.revenueIndex);
    }

    function accrued(uint256 id) internal view returns (uint256 cashWad, uint256 remainderScaled) {
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        uint256 delta = LibStakingStorage.state().revenueIndex - a.revenueIndexPaid;
        uint256 whole = Math.mulDiv(a.effectiveWeight, delta, SCALE);
        uint256 fraction = mulmod(a.effectiveWeight, delta, SCALE) + a.revenueRemainderScaled;
        whole += fraction / SCALE;
        cashWad = LibUnits.floorCash(whole, LibBookStorage.state().cashQuantum);
        remainderScaled = fraction % SCALE + (whole - cashWad) * SCALE;
    }

    function checkpoint(uint256 id) internal {
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        (uint256 earned, uint256 remainder) = accrued(id);
        a.claimableRevenueWad += earned;
        a.revenueRemainderScaled = remainder;
        a.revenueIndexPaid = LibStakingStorage.state().revenueIndex;
    }
}
