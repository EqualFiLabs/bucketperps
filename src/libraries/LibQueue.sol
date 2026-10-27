// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccounts } from "./LibAccounts.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibUnits } from "./LibUnits.sol";
import { ClaimPortion } from "../types/TradingTypes.sol";
import { LibBook } from "./LibBook.sol";
import { LibCash } from "./LibCash.sol";

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
    error InvalidClaimPortion();
    error DuplicateClaim();
    event ClaimHarvested(
        uint256 indexed claimId,
        uint256 indexed positionId,
        uint256 paidWad,
        uint256 remainingWad,
        uint256 sideBucketDebitWad
    );

    event ClaimQueued(uint256 indexed claimId, uint256 indexed positionId, uint256 amountWad);
    event ClaimConsumed(
        uint256 indexed claimId,
        uint256 indexed positionId,
        uint256 indexed tradeId,
        uint256 amountWad,
        uint256 remainingWad
    );

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

    function harvest(uint256 maxVisits) internal returns (uint256 paid) {
        if (maxVisits == 0 || maxVisits > MAX_VISITS) revert InvalidBound();
        LibCash.requireBacking();
        State storage s = state();
        LibBookStorage.State storage b = LibBookStorage.state();
        uint256 head = s.headId == 0 ? 1 : s.headId;
        for (uint256 visited; visited < maxVisits && head <= s.nextClaimId; ++visited) {
            Claim storage c = s.claims[head];
            if (c.remainingWad == 0) {
                ++head;
                continue;
            }
            uint256 amount = LibBook.houseCash();
            if (amount == 0) break;
            if (amount > c.remainingWad) amount = c.remainingWad;
            uint256 sideDebit = amount < b.sideBucketWad ? amount : b.sideBucketWad;
            b.sideBucketWad -= sideDebit;
            b.queuedDebtWad -= amount;
            c.remainingWad -= amount;
            b.accountCashWad += amount;
            LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[c.positionId];
            a.cashWad += amount;
            if (c.remainingWad == 0) --a.liveClaimCount;
            paid += amount;
            LibAccounts.syncActivity(c.positionId);
            emit ClaimHarvested(head, c.positionId, amount, c.remainingWad, sideDebit);
            if (c.remainingWad == 0) ++head;
            else break;
        }
        s.headId = head;
        if (b.queuedDebtWad == 0) {
            s.headId = s.nextClaimId + 1;
            b.sideBucketWad = 0;
        }
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

    function consume(uint256 positionId, uint256 tradeId, uint256 margin, ClaimPortion[] calldata portions)
        internal
    {
        if (portions.length == 0 || portions.length > MAX_PORTIONS) revert InvalidBound();
        State storage s = state();
        LibBookStorage.State storage b = LibBookStorage.state();
        uint256 total;
        for (uint256 i; i < portions.length; ++i) {
            ClaimPortion calldata p = portions[i];
            for (uint256 j; j < i; ++j) {
                if (portions[j].claimId == p.claimId) revert DuplicateClaim();
            }
            Claim storage c = s.claims[p.claimId];
            if (c.positionId != positionId || p.amountWad == 0 || p.amountWad > c.remainingWad) {
                revert InvalidClaimPortion();
            }
            LibUnits.toTokenUnits(p.amountWad, b.cashQuantum);
            total += p.amountWad;
            if (total > margin) revert InvalidClaimAmount();
            c.remainingWad -= p.amountWad;
            if (c.remainingWad == 0) --LibAccountsStorage.state().accounts[positionId].liveClaimCount;
            emit ClaimConsumed(p.claimId, positionId, tradeId, p.amountWad, c.remainingWad);
        }
        if (total != margin) revert InvalidClaimAmount();
        b.queuedDebtWad -= margin;
        b.committedDebtWad += margin;
        LibAccountsStorage.state().accounts[positionId].committedClaimMarginWad += margin;
        if (b.queuedDebtWad == 0) {
            s.headId = s.nextClaimId + 1;
            b.sideBucketWad = 0;
        }
    }
}
