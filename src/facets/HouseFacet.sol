// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibHouse } from "../libraries/LibHouse.sol";
import { LibBook } from "../libraries/LibBook.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibCash } from "../libraries/LibCash.sol";
import { LibUnits } from "../libraries/LibUnits.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract HouseFacet {
    error InvalidDonation();
    error SurplusUnavailable();

    event SettlementDonationClassified(uint256 amountWad);
    event SurplusConfigured(uint256 thresholdWad, address primary, address secondary, uint16 secondaryBps);
    event SurplusDistributed(
        uint256 amountWad, address primary, uint256 primaryWad, address secondary, uint256 secondaryWad
    );

    function unassignedSettlementUnits() public view returns (uint256) {
        LibCash.requireBacking();
        LibBookStorage.State storage b = LibBookStorage.state();
        return IERC20(b.settlementToken).balanceOf(address(this))
            - LibUnits.toTokenUnits(b.custodyWad, b.cashQuantum);
    }

    function classifySettlementDonation(uint256 amountWad) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibBookStorage.State storage b = LibBookStorage.state();
        uint256 units = LibUnits.toTokenUnits(amountWad, b.cashQuantum);
        if (units == 0 || units > unassignedSettlementUnits()) revert InvalidDonation();
        b.custodyWad += amountWad;
        emit SettlementDonationClassified(amountWad);
        LibGuard.exit();
    }

    function surplusConfiguration() external view returns (LibHouse.State memory) {
        return _configuration();
    }

    function configureSurplus(uint256 thresholdWad, address primary, address secondary, uint16 secondaryBps)
        external
    {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibHouse.State storage h = LibHouse.state();
        h.thresholdWad = thresholdWad;
        h.primaryReceiver = primary;
        h.secondaryReceiver = secondary;
        h.secondaryBps = secondaryBps;
        emit SurplusConfigured(thresholdWad, primary, secondary, secondaryBps);
        LibGuard.exit();
    }

    /// @notice Distribute realized excess from available house cash while the FIFO queue is empty.
    function distributeSurplus(uint256 amountWad) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibCash.requireBacking();
        LibBookStorage.State storage b = LibBookStorage.state();
        LibHouse.State memory h = _configuration();
        if (b.queuedDebtWad != 0 || b.realizedHousePnlWad <= 0) {
            revert SurplusUnavailable();
        }
        uint256 profit = uint256(b.realizedHousePnlWad);
        if (
            profit <= h.thresholdWad || amountWad == 0 || amountWad > profit - h.thresholdWad
                || amountWad > LibBook.houseCash()
        ) revert SurplusUnavailable();
        LibUnits.toTokenUnits(amountWad, b.cashQuantum);
        uint256 secondary = LibUnits.fee(amountWad, h.secondaryBps, b.cashQuantum);
        uint256 primary = amountWad - secondary;
        // amountWad <= positive realizedHousePnlWad, so this cast is bounded by int256.max.
        b.realizedHousePnlWad -= int256(amountWad);
        if (primary != 0) LibCash.sendExact(h.primaryReceiver, primary);
        if (secondary != 0) LibCash.sendExact(h.secondaryReceiver, secondary);
        emit SurplusDistributed(amountWad, h.primaryReceiver, primary, h.secondaryReceiver, secondary);
        LibGuard.exit();
    }

    function _configuration() private view returns (LibHouse.State memory h) {
        h = LibHouse.state();
        if (h.primaryReceiver == address(0)) h.primaryReceiver = LibProtocol.state().governor;
    }
}
