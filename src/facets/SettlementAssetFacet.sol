// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStaticsDollarCore } from "../interfaces/IStaticsDollarCore.sol";
import { LibDollar } from "../libraries/LibDollar.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibCash } from "../libraries/LibCash.sol";
import { LibUnits } from "../libraries/LibUnits.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibControls } from "../libraries/LibControls.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract SettlementAssetFacet {
    using SafeERC20 for IERC20;
    event DollarMigrationConfigured(address indexed core, address indexed dollar, uint256 profileId);
    event SettlementAssetMigrated(
        address indexed usdg,
        address indexed dollar,
        uint256 usdgUnits,
        uint256 dollarUnits,
        uint256 accountedCustodyWad
    );

    function dollarMigrationState() external view returns (LibDollar.State memory) {
        return LibDollar.state();
    }

    /// @notice One fixed endpoint/profile binding. Remains unset until source qualification is complete.
    function configureDollarMigration(address core, address dollar, uint256 profileId) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibDollar.consume(keccak256(abi.encode("dollar-binding", core, dollar, profileId)));
        LibDollar.State storage s = LibDollar.state();
        LibBookStorage.State storage b = LibBookStorage.state();
        if (
            s.core != address(0) || core.code.length == 0 || dollar == b.settlementToken
                || IERC20Metadata(dollar).decimals() != 18
        ) revert LibDollar.InvalidConversion();
        IStaticsDollarCore c = IStaticsDollarCore(core);
        IStaticsDollarCore.StableCollateralProfile memory profile = c.collateralProfile(profileId);
        if (
            c.staticsDollar() != dollar || profile.collateralToken != b.settlementToken
                || profile.kind != IStaticsDollarCore.ProfileKind.Pegged
                || profile.decimals != IERC20Metadata(b.settlementToken).decimals()
        ) revert LibDollar.InvalidConversion();
        s.usdg = b.settlementToken;
        s.usdgQuantum = b.cashQuantum;
        s.dollar = dollar;
        s.core = core;
        s.profileId = profileId;
        uint256 units = LibUnits.toTokenUnits(1e18, s.usdgQuantum);
        LibDollar.requireMintQuote(1e18, units);
        LibDollar.requireRedemptionQuote(1e18, units);
        emit DollarMigrationConfigured(core, dollar, profileId);
        LibGuard.exit();
    }

    function migrateUsdGToUsdStx() external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibControls.requireClear(LibControls.CONVERSION);
        LibDollar.State storage s = LibDollar.state();
        if (s.core == address(0) || s.migrated) revert LibDollar.InvalidConversion();
        LibDollar.consume(keccak256(abi.encode("dollar-migration", s.core, s.dollar, s.profileId)));
        LibCash.requireBacking();
        LibBookStorage.State storage b = LibBookStorage.state();
        IERC20 usdg = IERC20(s.usdg);
        IERC20 dollar = IERC20(s.dollar);
        uint256 units = usdg.balanceOf(address(this));
        uint256 wad = LibUnits.toWad(units, s.usdgQuantum);
        uint256 beforeDollar = dollar.balanceOf(address(this));
        if (wad != 0) {
            LibDollar.requireMintQuote(wad, units);
            usdg.forceApprove(s.core, units);
            uint256 spent = IStaticsDollarCore(s.core).mintPegged(s.profileId, wad, units, address(this));
            usdg.forceApprove(s.core, 0);
            if (
                spent != units || usdg.balanceOf(address(this)) != 0
                    || dollar.balanceOf(address(this)) != beforeDollar + wad
            ) revert LibDollar.InvalidConversion();
        }
        s.migrated = true;
        b.settlementToken = s.dollar;
        b.cashQuantum = 1;
        LibCash.requireBacking();
        emit SettlementAssetMigrated(s.usdg, s.dollar, units, wad, b.custodyWad);
        LibGuard.exit();
    }
}
