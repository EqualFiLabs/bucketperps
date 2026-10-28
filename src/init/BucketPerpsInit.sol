// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { AccountsInit } from "./AccountsInit.sol";
import { CashInit } from "./CashInit.sol";
import { OracleInit } from "./OracleInit.sol";
import { RewardsInit } from "./RewardsInit.sol";
import { OperatorRouterInit } from "./OperatorRouterInit.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibMarkets } from "../libraries/LibMarkets.sol";
import { LibRewards } from "../libraries/LibRewards.sol";
import { LibControls } from "../libraries/LibControls.sol";
import { LibHouse } from "../libraries/LibHouse.sol";

/// @notice Fixed bootstrap orchestration; no operational selector is installed for this contract.
contract BucketPerpsInit {
    address private immutable accounts = address(new AccountsInit());
    address private immutable cash = address(new CashInit());
    address private immutable oracle = address(new OracleInit());
    address private immutable rewards = address(new RewardsInit());
    address private immutable router = address(new OperatorRouterInit());

    struct Config {
        address positionNFT;
        address staticsDiamond;
        address settlementToken;
        address staticsToken;
        address executionOracle;
        address operatorRouter;
        bytes32 marketId;
        bytes32 streamId;
        LibMarkets.Risk risk;
        LibMarkets.Terms terms;
        uint256 globalOiCapWad;
        uint256 rewardUnitsPerDollar;
        uint64 dependencyDelay;
        uint256 surplusThresholdWad;
        address surplusPrimary;
        address surplusSecondary;
        uint16 surplusSecondaryBps;
    }

    error InvalidInitialization();
    event LaunchConfigured(bytes32 indexed marketId, Config configuration);

    function initialize(Config calldata c) external {
        if (!LibProtocol.state().initializing) revert InvalidInitialization();
        _run(accounts, abi.encodeCall(AccountsInit.initialize, (c.positionNFT, c.staticsDiamond)));
        _run(cash, abi.encodeCall(CashInit.initialize, (c.settlementToken)));
        _run(oracle, abi.encodeCall(OracleInit.initialize, (c.executionOracle)));
        _run(rewards, abi.encodeCall(RewardsInit.initialize, (c.staticsToken)));
        _run(router, abi.encodeCall(OperatorRouterInit.initialize, (c.operatorRouter)));
        if (c.marketId == bytes32(0) || c.streamId == bytes32(0)) revert LibMarkets.InvalidMarket();
        LibMarkets.validateTerms(c.terms);
        LibMarkets.State storage m = LibMarkets.state();
        m.markets[c.marketId].streamId = c.streamId;
        m.markets[c.marketId].risk = c.risk;
        m.markets[c.marketId].currentTermsVersion = 1;
        m.versions[c.marketId][1] = c.terms;
        m.globalOiCapWad = c.globalOiCapWad;
        LibRewards.state().rewardUnitsPerDollar = c.rewardUnitsPerDollar;
        LibControls.state().safetyDelay = c.dependencyDelay;
        LibHouse.State storage h = LibHouse.state();
        h.thresholdWad = c.surplusThresholdWad;
        h.primaryReceiver = c.surplusPrimary;
        h.secondaryReceiver = c.surplusSecondary;
        h.secondaryBps = c.surplusSecondaryBps;
        emit LaunchConfigured(c.marketId, c);
    }

    function _run(address target, bytes memory data) private {
        (bool ok, bytes memory result) = target.delegatecall(data);
        if (!ok) {
            assembly { revert(add(result, 32), mload(result)) }
        }
    }
}
