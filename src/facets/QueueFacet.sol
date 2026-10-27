// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibQueue } from "../libraries/LibQueue.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract QueueFacet {
    function queueState() external view returns (uint256 headId, uint256 lastId, uint256 debtWad) {
        LibQueue.State storage s = LibQueue.state();
        return (s.headId == 0 ? 1 : s.headId, s.nextClaimId, LibBookStorage.state().queuedDebtWad);
    }

    function claimState(uint256 claimId) external view returns (LibQueue.Claim memory) {
        return LibQueue.state().claims[claimId];
    }

    /// @notice Bounded historical IDs, including consumed or paid tombstones.
    function accountClaimIds(uint256 positionId, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory ids, uint256 nextCursor)
    {
        if (limit == 0 || limit > LibQueue.MAX_PAGE) revert LibQueue.InvalidBound();
        uint256[] storage all = LibQueue.state().accountClaimIds[positionId];
        if (cursor > all.length) revert LibQueue.InvalidBound();
        uint256 count = all.length - cursor;
        if (count > limit) count = limit;
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = all[cursor + i];
        }
        return (ids, cursor + count);
    }

    function queueBounds() external pure returns (uint256 visits, uint256 portions, uint256 page) {
        return (LibQueue.MAX_VISITS, LibQueue.MAX_PORTIONS, LibQueue.MAX_PAGE);
    }

    function harvest(uint256 maxEntries) external returns (uint256 paidWad) {
        LibGuard.enter();
        paidWad = LibQueue.harvest(maxEntries);
        LibGuard.exit();
    }

    function advanceQueue(uint256 maxVisits) external returns (uint256 headId) {
        LibGuard.enter();
        headId = LibQueue.advance(maxVisits);
        LibGuard.exit();
    }
}
