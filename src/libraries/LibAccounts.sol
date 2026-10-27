// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";

library LibAccounts {
    error NotPositionOwner();
    error AccountsNotConfigured();

    function owner(uint256 positionId) internal view returns (address) {
        address nft = LibAccountsStorage.state().positionNFT;
        if (nft == address(0)) revert AccountsNotConfigured();
        return IERC721(nft).ownerOf(positionId);
    }

    function requireOwner(uint256 positionId) internal view {
        if (owner(positionId) != msg.sender) revert NotPositionOwner();
    }
}
