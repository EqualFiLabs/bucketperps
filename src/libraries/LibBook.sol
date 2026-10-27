// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibBookStorage } from "./LibBookStorage.sol";

library LibBook {
    error InvalidBook();

    function houseCash() internal view returns (uint256 cash) {
        LibBookStorage.State storage b = LibBookStorage.state();
        cash = b.custodyWad - b.accountCashWad - b.lockedCashMarginWad - b.fundedPayablesWad;
        if (b.sideBucketWad > cash) revert InvalidBook();
    }

    function directBudget() internal view returns (uint256) {
        if (LibBookStorage.state().queuedDebtWad != 0) return 0;
        return houseCash();
    }
}
