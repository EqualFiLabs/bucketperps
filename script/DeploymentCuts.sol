// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { Script } from "forge-std/Script.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";
import { AccountFacet } from "../src/facets/AccountFacet.sol";
import { CashFacet } from "../src/facets/CashFacet.sol";
import { ControlFacet } from "../src/facets/ControlFacet.sol";
import { FeeFacet } from "../src/facets/FeeFacet.sol";
import { HouseFacet } from "../src/facets/HouseFacet.sol";
import { LiquidationFacet } from "../src/facets/LiquidationFacet.sol";
import { MarketFacet } from "../src/facets/MarketFacet.sol";
import { QueueFacet } from "../src/facets/QueueFacet.sol";
import { RewardFacet } from "../src/facets/RewardFacet.sol";
import { SettlementAssetFacet } from "../src/facets/SettlementAssetFacet.sol";
import { SettlementFacet } from "../src/facets/SettlementFacet.sol";
import { StakingFacet } from "../src/facets/StakingFacet.sol";
import { TradingFacet } from "../src/facets/TradingFacet.sol";
import { ViewFacet } from "../src/facets/ViewFacet.sol";

/// @dev Deployment-only helper. Selector names are compile-time checked against each facet.
abstract contract DeploymentCuts is Script {
    function deployCuts() internal returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](14);
        bytes4[] memory s;
        s = new bytes4[](3);
        s[0] = AccountFacet.accountState.selector;
        s[1] = AccountFacet.hasUnresolvedAccountState.selector;
        s[2] = AccountFacet.syncAccountActivity.selector;
        cuts[0] = IDiamondCut.FacetCut(
            _deploy("AccountFacet.sol:AccountFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](2);
        s[0] = CashFacet.deposit.selector;
        s[1] = CashFacet.withdraw.selector;
        cuts[1] =
            IDiamondCut.FacetCut(_deploy("CashFacet.sol:CashFacet", ""), IDiamondCut.FacetCutAction.Add, s);
        s = new bytes4[](13);
        s[0] = ControlFacet.executeConversionFlags.selector;
        s[1] = ControlFacet.executeWrapCapacity.selector;
        s[2] = ControlFacet.finalizeProtocol.selector;
        s[3] = ControlFacet.safetyAction.selector;
        s[4] = ControlFacet.safetyDelay.selector;
        s[5] = ControlFacet.setSafetyDelays.selector;
        s[6] = ControlFacet.scheduleSafetyAction.selector;
        s[7] = ControlFacet.cancelSafetyAction.selector;
        s[8] = ControlFacet.executeOracle.selector;
        s[9] = ControlFacet.executeOperatorRouter.selector;
        s[10] = ControlFacet.pausedGroups.selector;
        s[11] = ControlFacet.pause.selector;
        s[12] = ControlFacet.unpause.selector;
        cuts[2] = IDiamondCut.FacetCut(
            _deploy("ControlFacet.sol:ControlFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](3);
        s[0] = FeeFacet.flushOperatorFees.selector;
        s[1] = FeeFacet.feePayables.selector;
        s[2] = FeeFacet.withdrawProtocolFees.selector;
        cuts[3] =
            IDiamondCut.FacetCut(_deploy("FeeFacet.sol:FeeFacet", ""), IDiamondCut.FacetCutAction.Add, s);
        s = new bytes4[](5);
        s[0] = HouseFacet.unassignedSettlementUnits.selector;
        s[1] = HouseFacet.classifySettlementDonation.selector;
        s[2] = HouseFacet.surplusConfiguration.selector;
        s[3] = HouseFacet.configureSurplus.selector;
        s[4] = HouseFacet.distributeSurplus.selector;
        cuts[4] =
            IDiamondCut.FacetCut(_deploy("HouseFacet.sol:HouseFacet", ""), IDiamondCut.FacetCutAction.Add, s);
        s = new bytes4[](4);
        s[0] = LiquidationFacet.liquidate.selector;
        s[1] = LiquidationFacet.keeperPayable.selector;
        s[2] = LiquidationFacet.totalKeeperPayable.selector;
        s[3] = LiquidationFacet.withdrawKeeperCredit.selector;
        cuts[5] = IDiamondCut.FacetCut(
            _deploy("LiquidationFacet.sol:LiquidationFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](6);
        s[0] = MarketFacet.configureMarket.selector;
        s[1] = MarketFacet.publishTerms.selector;
        s[2] = MarketFacet.setGlobalOiCap.selector;
        s[3] = MarketFacet.marketState.selector;
        s[4] = MarketFacet.economicTerms.selector;
        s[5] = MarketFacet.globalOpenInterest.selector;
        cuts[6] = IDiamondCut.FacetCut(
            _deploy("MarketFacet.sol:MarketFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](6);
        s[0] = QueueFacet.queueState.selector;
        s[1] = QueueFacet.claimState.selector;
        s[2] = QueueFacet.accountClaimIds.selector;
        s[3] = QueueFacet.queueBounds.selector;
        s[4] = QueueFacet.harvest.selector;
        s[5] = QueueFacet.advanceQueue.selector;
        cuts[7] =
            IDiamondCut.FacetCut(_deploy("QueueFacet.sol:QueueFacet", ""), IDiamondCut.FacetCutAction.Add, s);
        s = new bytes4[](5);
        s[0] = RewardFacet.setLossRewardRate.selector;
        s[1] = RewardFacet.wrap.selector;
        s[2] = RewardFacet.unwrap.selector;
        s[3] = RewardFacet.rewardState.selector;
        s[4] = RewardFacet.fundRewardInventory.selector;
        cuts[8] = IDiamondCut.FacetCut(
            _deploy("RewardFacet.sol:RewardFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](4);
        s[0] = SettlementAssetFacet.withdrawUsdG.selector;
        s[1] = SettlementAssetFacet.dollarMigrationState.selector;
        s[2] = SettlementAssetFacet.configureDollarMigration.selector;
        s[3] = SettlementAssetFacet.migrateUsdGToUsdStx.selector;
        cuts[9] = IDiamondCut.FacetCut(
            _deploy("SettlementAssetFacet.sol:SettlementAssetFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](1);
        s[0] = SettlementFacet.closePosition.selector;
        cuts[10] = IDiamondCut.FacetCut(
            _deploy("SettlementFacet.sol:SettlementFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](6);
        s[0] = StakingFacet.onAccountMultiplierChanged.selector;
        s[1] = StakingFacet.stake.selector;
        s[2] = StakingFacet.unstake.selector;
        s[3] = StakingFacet.claimStakerRevenue.selector;
        s[4] = StakingFacet.pendingStakerRevenue.selector;
        s[5] = StakingFacet.stakingTotals.selector;
        cuts[11] = IDiamondCut.FacetCut(
            _deploy("StakingFacet.sol:StakingFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](2);
        s[0] = TradingFacet.openPosition.selector;
        s[1] = TradingFacet.tradeState.selector;
        cuts[12] = IDiamondCut.FacetCut(
            _deploy("TradingFacet.sol:TradingFacet", ""), IDiamondCut.FacetCutAction.Add, s
        );
        s = new bytes4[](6);
        s[0] = ViewFacet.ledgerState.selector;
        s[1] = ViewFacet.accountOverview.selector;
        s[2] = ViewFacet.externalAccountIdentity.selector;
        s[3] = ViewFacet.accountTradeIds.selector;
        s[4] = ViewFacet.tradeContext.selector;
        s[5] = ViewFacet.rewardBacking.selector;
        cuts[13] =
            IDiamondCut.FacetCut(_deploy("ViewFacet.sol:ViewFacet", ""), IDiamondCut.FacetCutAction.Add, s);
    }

    function _deploy(string memory artifact, bytes memory arguments) internal returns (address deployed) {
        bytes memory code = abi.encodePacked(vm.getCode(artifact), arguments);
        assembly { deployed := create(0, add(code, 32), mload(code)) }
        require(deployed != address(0), "deployment failed");
    }
}
