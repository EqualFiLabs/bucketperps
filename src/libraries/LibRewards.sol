// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BucketRewardToken } from "../rewards/BucketRewardToken.sol";
import { LibUnits } from "./LibUnits.sol";
import { LibAccountsStorage } from "./LibAccountsStorage.sol";

library LibRewards {
    using SafeERC20 for IERC20;
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.rewards.v1");

    struct State {
        address staticsToken;
        address backingVault;
        address receipt;
        uint256 inventoryUnits;
        uint256 allocatedUnits;
        uint256 wrapCapacityUnits;
        uint256 rewardUnitsPerDollar;
        bool wrappingEnabled;
        bool unwrappingEnabled;
    }

    event LossRewardIssued(
        uint256 indexed positionId,
        uint256 indexed tradeId,
        uint256 lossBasisWad,
        uint256 unitsPerDollar,
        uint256 requestedUnits,
        uint256 issuedUnits,
        uint256 shortfallUnits
    );

    function rewardLoss(uint256 positionId, uint256 tradeId, uint256 lossBasisWad) internal {
        if (lossBasisWad == 0) return;
        uint256 rate = state().rewardUnitsPerDollar;
        uint256 requested = LibUnits.rewardUnits(lossBasisWad, rate);
        uint256 issued = issue(positionId, requested);
        emit LossRewardIssued(positionId, tradeId, lossBasisWad, rate, requested, issued, requested - issued);
    }

    error InvalidAmount();
    error InexactTransfer();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    /// @dev Internal issuance only; settlement supplies the loss-derived request.
    function issue(uint256 positionId, uint256 requested) internal returns (uint256 issued) {
        State storage s = state();
        issued = requested < s.inventoryUnits ? requested : s.inventoryUnits;
        if (issued == 0) return 0;
        s.inventoryUnits -= issued;
        s.allocatedUnits += issued;
        LibAccountsStorage.state().accounts[positionId].unstakedRewardUnits += issued;
        transferExact(address(this), s.backingVault, issued);
        BucketRewardToken(s.receipt).mint(issued);
    }

    function transferExact(address from, address to, uint256 units) internal {
        IERC20 token = IERC20(state().staticsToken);
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        if (from == address(this)) token.safeTransfer(to, units);
        else token.safeTransferFrom(from, to, units);
        if (token.balanceOf(from) + units != beforeFrom || token.balanceOf(to) != beforeTo + units) {
            revert InexactTransfer();
        }
    }
}
