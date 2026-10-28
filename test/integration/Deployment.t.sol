// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ProtocolFixture } from "../helpers/ProtocolFixture.sol";
import { DeployBucketPerps } from "../../script/DeployBucketPerps.s.sol";
import { BucketPerpsInit } from "../../src/init/BucketPerpsInit.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { RewardFacet } from "../../src/facets/RewardFacet.sol";
import { ViewFacet } from "../../src/facets/ViewFacet.sol";
import { ControlFacet } from "../../src/facets/ControlFacet.sol";
import { SettlementAssetFacet } from "../../src/facets/SettlementAssetFacet.sol";
import { CashFacet } from "../../src/facets/CashFacet.sol";
import { MarketFacet } from "../../src/facets/MarketFacet.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { LibRewards } from "../../src/libraries/LibRewards.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";
import { IDiamondLoupe } from "../../src/interfaces/IDiamondLoupe.sol";

contract DeploymentTest is ProtocolFixture {
    function _configuration() internal returns (BucketPerpsInit.Config memory c) {
        c.positionNFT = address(statics);
        c.staticsDiamond = address(statics);
        c.settlementToken = address(token);
        c.staticsToken = address(new CashTokenMock(18));
        c.executionOracle = address(oracle);
        c.operatorRouter = address(statics); // Identity fixture only; real router qualified separately.
        c.marketId = MARKET;
        c.streamId = STREAM;
        c.risk = _risk();
        c.terms = _terms();
        c.globalOiCapWad = 10_000_000e18;
        c.rewardUnitsPerDollar = 1e18;
        c.dependencyDelay = 1 days;
    }

    function testAtomicDeploymentInstallsOnlyProductionSelectorsAndLaunchState() public {
        BucketPerpsInit.Config memory c = _configuration();
        BucketPerpsDiamond d = new DeployBucketPerps().deploy(alice, bob, 0, c);
        (address governor, address guardian, uint64 delay, bool finalized) = d.protocolState();
        assertEq(governor, alice);
        assertEq(guardian, bob);
        assertEq(delay, 0);
        assertFalse(finalized);
        IDiamondLoupe.Facet[] memory facets = d.facets();
        assertEq(facets.length, 15);
        for (uint256 i; i < facets.length; ++i) {
            for (uint256 j; j < facets[i].functionSelectors.length; ++j) {
                bytes4 selector = facets[i].functionSelectors[j];
                assertEq(d.facetAddress(selector), facets[i].facetAddress);
                assertTrue(selector != bytes4(keccak256("seedEntitlement(uint256,uint256)")));
                assertTrue(selector != BucketPerpsInit.initialize.selector);
            }
        }
        LibRewards.State memory r = RewardFacet(address(d)).rewardState();
        assertEq(r.rewardUnitsPerDollar, 1e18);
        assertEq(r.wrapCapacityUnits, 0);
        assertFalse(r.wrappingEnabled);
        assertFalse(r.unwrappingEnabled);
        assertEq(ViewFacet(address(d)).ledgerState().book.cashQuantum, 1e12);
        assertEq(ControlFacet(address(d)).safetyDelay(), 1 days);
        assertEq(SettlementAssetFacet(address(d)).dollarMigrationState().core, address(0));
        assertEq(MarketFacet(address(d)).marketState(MARKET).streamId, STREAM);
        statics.configure(address(d), true);
        vm.startPrank(alice);
        token.mint(alice, 1e6);
        token.approve(address(d), 1e6);
        CashFacet(address(d)).deposit(1, 1e6);
        CashFacet(address(d)).withdraw(1, 1e18, alice);
        vm.stopPrank();
        assertEq(ViewFacet(address(d)).ledgerState().book.custodyWad, 0);
    }

    function testBootstrapDoesNotCreateNumericAdministrativeRestrictions() public {
        BucketPerpsInit.Config memory c = _configuration();
        c.risk.maxShortOiWad = 0;
        c.risk.minMarginWad = 0;
        c.risk.maxMarginWad = 0;
        c.dependencyDelay = 0;
        c.rewardUnitsPerDollar = 0;
        BucketPerpsDiamond d = new DeployBucketPerps().deploy(alice, bob, 0, c);
        assertEq(MarketFacet(address(d)).marketState(MARKET).risk.maxShortOiWad, 0);
        assertEq(ControlFacet(address(d)).safetyDelay(), 0);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        ControlFacet(address(d)).finalizeProtocol();
    }

    function testInitializerCannotBeCalledAsOperationalSetter() public {
        BucketPerpsInit.Config memory c = _configuration();
        BucketPerpsInit init = new BucketPerpsInit();
        vm.expectRevert(BucketPerpsInit.InvalidInitialization.selector);
        init.initialize(c);
    }
}
