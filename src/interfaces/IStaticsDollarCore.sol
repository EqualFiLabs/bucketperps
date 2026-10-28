// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @notice Pegged ABI from EqualFiLabs/statics revision 09f3612ecf20c5f2b077818655ec51cf543dada6.
/// @dev Interface presence does not establish the approved-consumer exemption requested in #142.
interface IStaticsDollarCore {
    enum ProfileKind {
        Volatile,
        Pegged
    }
    enum ProfileMode {
        Inactive,
        Active,
        ReduceOnly,
        Retired
    }
    enum ExitStatus {
        Available,
        Impaired,
        HealthUnavailable,
        Recovering,
        DownsideTransition
    }

    struct StableCollateralProfile {
        address collateralToken;
        address oracle;
        uint8 decimals;
        uint16 collateralRatioBps;
        uint16 priceBandBps;
        uint16 mintFeeBps;
        uint16 redemptionFeeBps;
        uint16 insuranceTargetBps;
        uint16 insuranceFeeBps;
        ProfileKind kind;
        ProfileMode mode;
        uint256 pegMinPriceWad;
        uint256 pegMaxPriceWad;
        uint256 activeSeriesId;
        uint256 accountedCollateral;
        uint256 insuranceReserve;
        uint256 seniorOutstanding;
        uint256 debtCeiling;
    }

    struct PeggedMintPreview {
        uint256 profileId;
        address collateralToken;
        uint256 staticsDollarMinted;
        uint256 principalCollateral;
        uint256 feeAmount;
        uint256 totalCollateralIn;
        uint256 priceWad;
    }

    struct PeggedRedemptionPreview {
        uint256 profileId;
        address collateralToken;
        uint256 staticsDollarBurned;
        uint256 grossCollateral;
        uint256 feeAmount;
        uint256 collateralOut;
        uint256 priceWad;
    }
    function staticsDollar() external view returns (address);
    function collateralProfile(uint256 profileId) external view returns (StableCollateralProfile memory);
    function previewPeggedMint(uint256 profileId, uint256 dollarAmount)
        external
        view
        returns (PeggedMintPreview memory);
    function previewPeggedRedemption(uint256 profileId, uint256 dollarAmount)
        external
        view
        returns (PeggedRedemptionPreview memory);
    function mintPegged(
        uint256 profileId,
        uint256 dollarAmount,
        uint256 maximumCollateralIn,
        address receiver
    ) external returns (uint256 collateralIn);
    function redeemPegged(
        uint256 profileId,
        uint256 dollarAmount,
        uint256 minimumCollateralOut,
        address receiver
    ) external returns (ExitStatus status, uint256 collateralOut);
}
