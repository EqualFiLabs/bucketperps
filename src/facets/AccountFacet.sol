// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract AccountFacet {
    function accountState(uint256 positionId) external view returns (LibAccountsStorage.Account memory) {
        return LibAccountsStorage.state().accounts[positionId];
    }

    function hasUnresolvedAccountState(uint256 positionId) external view returns (bool) {
        return LibAccounts.hasUnresolvedState(LibAccountsStorage.state().accounts[positionId]);
    }

    /// @notice Permissionless reconciliation; occupied accounts cannot have their leg removed.
    function syncAccountActivity(uint256 positionId) external {
        LibGuard.enter();
        LibAccounts.syncActivity(positionId);
        LibGuard.exit();
    }
}
