// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibControls } from "./LibControls.sol";
import { IStaticsDollarCore } from "../interfaces/IStaticsDollarCore.sol";

library LibDollar {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.dollar.v1");

    struct State {
        address usdg;
        address dollar;
        address core;
        uint256 profileId;
        uint256 usdgQuantum;
        bool migrated;
    }
    error InvalidConversion();
    error ActionNotReady();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function consume(bytes32 operation) internal {
        uint256 readyAt = LibControls.state().pending[operation];
        if (readyAt == 0 || block.timestamp < readyAt) revert ActionNotReady();
        delete LibControls.state().pending[operation];
    }

    function requireMintQuote(uint256 amountWad, uint256 units) internal view {
        State storage s = state();
        IStaticsDollarCore.PeggedMintPreview memory q =
            IStaticsDollarCore(s.core).previewPeggedMint(s.profileId, amountWad);
        if (
            q.profileId != s.profileId || q.collateralToken != s.usdg || q.staticsDollarMinted != amountWad
                || q.principalCollateral != units || q.totalCollateralIn != units || q.feeAmount != 0
                || q.priceWad != 1e18
        ) revert InvalidConversion();
    }

    function requireRedemptionQuote(uint256 amountWad, uint256 units) internal view {
        State storage s = state();
        IStaticsDollarCore.PeggedRedemptionPreview memory q =
            IStaticsDollarCore(s.core).previewPeggedRedemption(s.profileId, amountWad);
        if (
            q.profileId != s.profileId || q.collateralToken != s.usdg || q.staticsDollarBurned != amountWad
                || q.grossCollateral != units || q.collateralOut != units || q.feeAmount != 0
                || q.priceWad != 1e18
        ) revert InvalidConversion();
    }
}
