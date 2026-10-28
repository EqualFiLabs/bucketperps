// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";
import { OperatorFeeRouter } from "../../lib/operator-fee-router/src/OperatorFeeRouter.sol";
import {
    MockVault,
    MockOperatorCollection,
    MockActivationRegistry
} from "../../lib/operator-fee-router/test/mocks/MockOperatorSystem.sol";
import { StaticsExecutionOracle } from "statics-oracle/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as ExternalOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";
import { DataStreamsV3 } from "statics-oracle/libraries/DataStreamsV3.sol";
import { ExecutionVerifierMock } from "lib/statics-oracle/test/mocks/ExecutionOracleMocks.sol";
import { FeeFacet } from "../../src/facets/FeeFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

contract HealthySequencerFixture {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 0, 1, block.timestamp, 1);
    }
}

/// @dev Actual adapter/router code with explicit verifier, sequencer and Genesis fixtures.
/// Does not qualify Chainlink authentication, live billing or the missing Statics #143 bridge.
contract PinnedDependenciesTest is ControlProtocolFixture {
    function testRealRouterBootstrapContributionAndClaim() public {
        MockVault vault = new MockVault();
        MockOperatorCollection collection = new MockOperatorCollection(address(vault));
        MockActivationRegistry registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        collection.setOwner(1, alice);
        OperatorFeeRouter router =
            new OperatorFeeRouter(address(collection), address(registry), address(vault), address(this));
        while (router.nextOperatorId() <= 5555) router.bootstrapOperators(100);
        router.finalizeBootstrap();
        router.registerRewardAsset(address(token));
        assertEq(router.totalEffectiveWeight(), 10_000);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](1);
        s[0] = FeeFacet.flushOperatorFees.selector;
        cuts[0] = _cut(address(new FeeFacet()), s);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        controls.scheduleSafetyAction(keccak256(abi.encode("operator-router", address(router))));
        controls.executeOperatorRouter(address(router));
        _earnReceipts(1, alice);
        feeFacet.flushOperatorFees(0.04e18);
        assertEq(router.pendingOperatorRewards(1, address(token)), 40_000);
        vm.prank(alice);
        router.claimOperatorRewards(1, address(token), alice);
        assertEq(token.balanceOf(alice), 40_000);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.allowance(address(diamond), address(router)), 0);
    }

    function testRealOracleNormalizesSelectsAndSettlesThroughDiamond() public {
        ExecutionVerifierMock verifier = new ExecutionVerifierMock();
        StaticsExecutionOracle adapter = new StaticsExecutionOracle(address(this), address(verifier), 8);
        bytes32 stream = bytes32((uint256(3) << 240) | 1);
        adapter.registerMarket(MARKET, ExternalOracle.ExecutionMarketConfigInput(stream, 5, 10, 8));
        adapter.enableMarket(MARKET);
        adapter.setSequencerConfig(address(new HealthySequencerFixture()), 60);
        adapter.setAuthorizedConsumer(address(diamond), true);
        controls.scheduleSafetyAction(keccak256(abi.encode("oracle", address(adapter))));
        controls.executeOracle(address(adapter));
        markets.configureMarket(MARKET, stream, _risk());
        bytes[] memory reports = new bytes[](2);
        reports[0] = hex"a1";
        reports[1] = hex"a2";
        verifier.accept(
            reports[0],
            abi.encode(
                DataStreamsV3.Report(
                    stream,
                    uint32(block.timestamp - 20),
                    uint32(block.timestamp - 18),
                    0,
                    0,
                    uint32(block.timestamp + 1000),
                    50_000e8,
                    50_000e8,
                    50_000e8
                )
            )
        );
        verifier.accept(reports[1], _body(stream, 50_000e8));
        vm.prank(alice);
        uint256 id =
            trading.openPosition(1, _params(true, FundingSource.Cash), new ClaimPortion[](0), reports);
        assertEq(trading.tradeState(id).entryPrice1e18, 50_000e18);
        (reports[0], reports[1]) = (reports[1], reports[0]);
        vm.prank(bob);
        uint256 other =
            trading.openPosition(2, _params(false, FundingSource.Cash), new ClaimPortion[](0), reports);
        assertEq(trading.tradeState(other).entryPrice1e18, 50_000e18);
        reports = new bytes[](1);
        reports[0] = hex"b1";
        verifier.accept(reports[0], _body(stream, 49_900e8));
        vm.prank(alice);
        settlement.closePosition(1, id, block.timestamp, reports);
        assertEq(accounts.accountState(1).cashWad, 980e18);
        adapter.setAuthorizedConsumer(address(diamond), false);
        vm.prank(bob);
        vm.expectRevert();
        settlement.closePosition(2, other, block.timestamp, reports);
        assertFalse(trading.tradeState(other).settled);
    }

    function _body(bytes32 stream, int192 price) private view returns (bytes memory) {
        return abi.encode(
            DataStreamsV3.Report(
                stream,
                uint32(block.timestamp - 7),
                uint32(block.timestamp - 3),
                0,
                0,
                uint32(block.timestamp + 1000),
                price,
                price,
                price
            )
        );
    }
}
