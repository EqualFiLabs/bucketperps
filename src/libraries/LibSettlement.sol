// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibBook } from "./LibBook.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { LibAccounts } from "./LibAccounts.sol";
import { LibQueue } from "./LibQueue.sol";
import { LibUnits } from "./LibUnits.sol";

library LibSettlement {
    struct Payout {
        uint256 paidWad;
        uint256 queuedWad;
        uint256 claimId;
    }

    /// @dev Cash principal is handled separately. This only changes funding/debt timing, not PnL.
    function payout(uint256 positionId, uint256 entitlement) internal returns (Payout memory result) {
        if (entitlement == 0) return result;
        LibUnits.toTokenUnits(entitlement, LibBookStorage.state().cashQuantum);
        uint256 budget = LibBook.directBudget();
        result.paidWad = entitlement < budget ? entitlement : budget;
        if (result.paidWad != 0) {
            LibAccountsStorage.state().accounts[positionId].cashWad += result.paidWad;
            LibBookStorage.state().accountCashWad += result.paidWad;
        }
        result.queuedWad = entitlement - result.paidWad;
        if (result.queuedWad != 0) result.claimId = LibQueue.enqueue(positionId, result.queuedWad);
        LibAccounts.syncActivity(positionId);
    }
}
