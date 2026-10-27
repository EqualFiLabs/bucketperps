// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";
import { OracleInit } from "../../src/init/OracleInit.sol";
import { LibOracle } from "../../src/libraries/LibOracle.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";
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

    function testFuzz_AdapterFailuresAreNotSwallowed(bytes4 selector, uint256 detail) public {
        bytes memory reason = abi.encodeWithSelector(selector, detail);
        oracle.setFailure(reason);
        vm.expectRevert(reason);
        client.quote(MARKET, STREAM, new bytes[](0));
        assertEq(oracle.calls(), 0);
    }

    function test_ReportAndSequencerRejectionsPropagateExactly() public {
        // Adapter policy is not duplicated here. These are opaque simulated terminal errors.
        string[8] memory errors = [
            "WrongStreamId(bytes32,bytes32)",
            "ReportExpired(uint32,uint256)",
            "InvalidReportPrice(int192)",
            "ReportWindowUnavailable(uint256)",
            "OverlappingReportWindows(uint256,uint256)",
            "SequencerDown()",
            "UnauthorizedConsumer(address)",
            "VerifierResponseLengthMismatch(uint256,uint256)"
        ];
        for (uint256 i; i < errors.length; ++i) {
            bytes memory reason = abi.encodePacked(bytes4(keccak256(bytes(errors[i]))), bytes32(i));
            oracle.setFailure(reason);
            vm.expectRevert(reason);
            client.quote(MARKET, STREAM, new bytes[](0));
        }
    }

    function test_ClientRejectsUnexpectedStreamAndUnsupportedPriceDomain() public {
        bytes[] memory reports = new bytes[](0);
        vm.expectRevert(LibOracle.UnexpectedStream.selector);
        client.quote(MARKET, bytes32(0), reports);
        assertEq(oracle.calls(), 0);
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(1e18, 100, 99, 101, bytes32(uint256(1))));
        vm.expectRevert(LibOracle.UnexpectedStream.selector);
        client.quote(MARKET, STREAM, reports);
        assertEq(oracle.calls(), 0);
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(0, 100, 99, 101, STREAM));
        vm.expectRevert(LibPnl.InvalidPrice.selector);
        client.quote(MARKET, STREAM, reports);
        oracle.setResponse(
            IStaticsExecutionOracle.ExecutionPrice(uint256(type(uint120).max) + 1, 100, 99, 101, STREAM)
        );
        vm.expectRevert(LibPnl.InvalidPrice.selector);
        client.quote(MARKET, STREAM, reports);
    }

    function test_IdenticalAuthenticatedPriceHasNoCallerOrEndpointPreference() public {
        bytes[] memory reports = new bytes[](2);
        reports[0] = hex"01";
        reports[1] = hex"02";
        vm.prank(makeAddr("first independent caller"));
        IStaticsExecutionOracle.ExecutionPrice memory first = client.quote(MARKET, STREAM, reports);
        reports[0] = hex"02";
        reports[1] = hex"01";
        vm.prank(makeAddr("second independent caller"));
        IStaticsExecutionOracle.ExecutionPrice memory second = client.quote(MARKET, STREAM, reports);
        assertEq(abi.encode(first), abi.encode(second));
        assertEq(oracle.lastBundleHash(), keccak256(abi.encode(reports)));
        assertEq(oracle.calls(), 2);
    }

    function test_OracleCannotReenterSharedFinancialBoundary() public {
        bytes[] memory reports = new bytes[](0);
        oracle.setCallback(
            address(client), abi.encodeCall(OracleClientHarness.quote, (MARKET, STREAM, reports))
        );
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        client.quote(MARKET, STREAM, reports);
        assertEq(oracle.calls(), 0);
    }

    function test_OracleDependencyCannotBeReinitialized() public {
        OracleInit another = new OracleInit();
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        bytes memory data = abi.encodeCall(OracleInit.initialize, (address(oracle)));
        BucketPerpsDiamond diamond = BucketPerpsDiamond(payable(address(client)));
        diamond.scheduleDiamondCut(empty, address(another), data);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(OracleInit.InvalidInitialization.selector);
        diamond.diamondCut(empty, address(another), data);
    }
}
