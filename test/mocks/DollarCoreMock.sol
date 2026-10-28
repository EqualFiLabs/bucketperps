// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IStaticsDollarCore } from "../../src/interfaces/IStaticsDollarCore.sol";
import { CashTokenMock } from "./CashTokenMock.sol";

/// @dev Exact consumer fixture, not evidence that Statics #142 is implemented.
contract DollarCoreMock is IStaticsDollarCore {
    CashTokenMock public immutable collateral;
    CashTokenMock public immutable dollar;
    uint256 public immutable quantum;
    uint256 public feeUnits;
    ExitStatus public exitStatus;
    bool public inexact;

    constructor(CashTokenMock collateral_, CashTokenMock dollar_) {
        collateral = collateral_;
        dollar = dollar_;
        quantum = 10 ** (18 - collateral_.decimals());
    }

    function configure(uint256 fee, ExitStatus status, bool bad) external {
        feeUnits = fee;
        exitStatus = status;
        inexact = bad;
    }

    function staticsDollar() external view returns (address) {
        return address(dollar);
    }

    function collateralProfile(uint256) external view returns (StableCollateralProfile memory p) {
        p.collateralToken = address(collateral);
        p.decimals = collateral.decimals();
        p.kind = ProfileKind.Pegged;
        p.mode = ProfileMode.Active;
    }

    function previewPeggedMint(uint256 id, uint256 amount) external view returns (PeggedMintPreview memory) {
        uint256 units = amount / quantum;
        return PeggedMintPreview(id, address(collateral), amount, units, feeUnits, units + feeUnits, 1e18);
    }

    function previewPeggedRedemption(uint256 id, uint256 amount)
        external
        view
        returns (PeggedRedemptionPreview memory)
    {
        uint256 units = amount / quantum;
        PeggedRedemptionPreview memory result =
            PeggedRedemptionPreview(id, address(collateral), amount, units, feeUnits, units - feeUnits, 1e18);
        return result;
    }

    function mintPegged(uint256, uint256 amount, uint256 maximum, address receiver)
        external
        returns (uint256 units)
    {
        units = amount / quantum + feeUnits;
        require(units <= maximum);
        collateral.transferFrom(msg.sender, address(this), units);
        dollar.mint(receiver, inexact ? amount - 1 : amount);
    }

    function redeemPegged(uint256, uint256 amount, uint256 minimum, address receiver)
        external
        returns (ExitStatus, uint256 units)
    {
        if (exitStatus != ExitStatus.Available) return (exitStatus, 0);
        units = amount / quantum - feeUnits;
        require(units >= minimum);
        dollar.burn(msg.sender, amount);
        collateral.transfer(receiver, inexact ? units - 1 : units);
        return (exitStatus, units);
    }
}
