// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccounts } from "./LibAccounts.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibUnits } from "./LibUnits.sol";

library LibQueue {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.queue.v1");
    uint256 internal constant MAX_VISITS = 128;
    uint256 internal constant MAX_PAGE = 64;
    uint256 internal constant MAX_PORTIONS = 32;

    struct Claim {
        uint256 positionId;
        uint256 remainingWad;
    }

    struct State {
        uint256 headId;
        uint256 nextClaimId;
        mapping(uint256 claimId => Claim claim) claims;
        mapping(uint256 positionId => uint256[] claimIds) accountClaimIds;
    }

    error InvalidBound();
    error InvalidClaimAmount();

    event ClaimQueued(uint256 indexed claimId, uint256 indexed positionId, uint256 amountWad);

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    /// @dev The caller records the economic reason for the entitlement, independently of debt timing.
    function enqueue(uint256 positionId, uint256 amount) internal returns (uint256 id) {
        if (amount == 0) revert InvalidClaimAmount();
        LibBookStorage.State storage b = LibBookStorage.state();
        LibUnits.toTokenUnits(amount, b.cashQuantum);
        State storage s = state();
        id = ++s.nextClaimId;
        if (b.queuedDebtWad == 0) s.headId = id;
        s.claims[id] = Claim(positionId, amount);
        s.accountClaimIds[positionId].push(id);
        b.queuedDebtWad += amount;
        ++LibAccountsStorage.state().accounts[positionId].liveClaimCount;
        LibAccounts.syncActivity(positionId);
        emit ClaimQueued(id, positionId, amount);
    }

    function advance(uint256 maxVisits) internal returns (uint256 head) {
        if (maxVisits == 0 || maxVisits > MAX_VISITS) revert InvalidBound();
        State storage s = state();
        head = s.headId == 0 ? 1 : s.headId;
        for (uint256 visited; visited < maxVisits && head <= s.nextClaimId; ++visited) {
            if (s.claims[head].remainingWad != 0) break;
            ++head;
        }
        s.headId = head;
    }
}
