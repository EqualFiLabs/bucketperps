// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";
import { IStaticsAccountBridge } from "../interfaces/IStaticsAccountBridge.sol";

library LibAccounts {
    bytes32 internal constant MODULE_TYPE = keccak256("bucketperps.account.v1");

    error NotPositionOwner();
    error AccountsNotConfigured();

    event AccountActivityChanged(uint256 indexed positionId, bool active);

    function owner(uint256 positionId) internal view returns (address) {
        address nft = LibAccountsStorage.state().positionNFT;
        if (nft == address(0)) revert AccountsNotConfigured();
        return IERC721(nft).ownerOf(positionId);
    }

    function requireOwner(uint256 positionId) internal view {
        if (owner(positionId) != msg.sender) revert NotPositionOwner();
    }

    function hasUnresolvedState(LibAccountsStorage.Account storage a) internal view returns (bool) {
        return a.cashWad != 0 || a.committedClaimMarginWad != 0 || a.unstakedRewardUnits != 0
            || a.rawStakeUnits != 0 || a.effectiveWeight != 0 || a.claimableRevenueWad != 0
            || a.openTradeCount != 0 || a.liveClaimCount != 0;
    }

    /// @dev Call under the shared guard after every financial mutation. Bridge failure rolls back it all.
    function syncActivity(uint256 positionId) internal {
        owner(positionId);
        LibAccountsStorage.State storage s = LibAccountsStorage.state();
        LibAccountsStorage.Account storage a = s.accounts[positionId];
        bool active = hasUnresolvedState(a);
        if (active == a.externalStateActive) return;
        a.externalStateActive = active;
        IStaticsAccountBridge bridge = IStaticsAccountBridge(s.staticsDiamond);
        if (active) {
            bridge.attachExternalAccountLeg(positionId, MODULE_TYPE, bytes32(positionId));
        } else {
            bridge.detachExternalAccountLeg(positionId, MODULE_TYPE, bytes32(positionId));
        }
        emit AccountActivityChanged(positionId, active);
    }
}
