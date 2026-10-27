// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";
import { OracleInit } from "../../src/init/OracleInit.sol";
import { LibOracle } from "../../src/libraries/LibOracle.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { ExecutionOracleMock } from "../mocks/ExecutionOracleMock.sol";

contract OracleClientHarness {
    function quote(bytes32 market, bytes32 stream, bytes[] calldata reports)
        external
        returns (IStaticsExecutionOracle.ExecutionPrice memory result)
    {
        LibGuard.enter();
        result = LibOracle.verify(market, stream, reports);
        LibGuard.exit();
    }
}

contract OracleClientTest is Test {
    bytes32 internal constant MARKET = keccak256("fixture market");
    bytes32 internal constant STREAM = keccak256("fixture stream");
    OracleClientHarness internal client;
    ExecutionOracleMock internal oracle;

    function setUp() public {
        oracle = new ExecutionOracleMock();
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(50_000e18, 100, 99, 101, STREAM));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OracleClientHarness.quote.selector;
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut(
            address(new OracleClientHarness()), IDiamondCut.FacetCutAction.Add, selectors
        );
        BucketPerpsDiamond diamond = new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap({
                governor: address(this),
                guardian: makeAddr("guardian"),
                upgradeDelay: 1 days,
                cuts: cuts,
                init: address(new OracleInit()),
                data: abi.encodeCall(OracleInit.initialize, (address(oracle)))
            })
        );
        client = OracleClientHarness(address(diamond));
    }

    function test_ReportsAreForwardedUnchangedAndDiamondIsConsumer() public {
        bytes[] memory reports = new bytes[](2);
        reports[0] = hex"123456";
        reports[1] = hex"abcdef01";
        vm.prank(makeAddr("independent caller"));
        IStaticsExecutionOracle.ExecutionPrice memory price = client.quote(MARKET, STREAM, reports);
        assertEq(price.price1e18, 50_000e18);
        assertEq(price.referenceTimestamp, 100);
        assertEq(price.validFromTimestamp, 99);
        assertEq(price.observationsTimestamp, 101);
        assertEq(price.streamId, STREAM);
        assertEq(oracle.lastBundleHash(), keccak256(abi.encode(reports)));
        assertEq(oracle.lastMarket(), MARKET);
        assertEq(oracle.lastConsumer(), address(client));
    }

    function test_DirectInitializerCannotConfigureDependency() public {
        OracleInit init = new OracleInit();
        vm.expectRevert(OracleInit.InvalidInitialization.selector);
        init.initialize(address(oracle));
    }
}
