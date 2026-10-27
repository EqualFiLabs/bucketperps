// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";
import { AccountsInit } from "../../src/init/AccountsInit.sol";
import { OracleInit } from "../../src/init/OracleInit.sol";
import { AccountFacet } from "../../src/facets/AccountFacet.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";
import { LibUnits } from "../../src/libraries/LibUnits.sol";
import { ActivityHarness } from "../unit/AccountLifecycle.t.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";
import { ExecutionOracleMock } from "../mocks/ExecutionOracleMock.sol";
import { LibOracle } from "../../src/libraries/LibOracle.sol";

/// @dev Acceptance harness, not an executable trading path or an external dependency qualification.
contract FoundationPreview {
    function preview(uint256 id, bytes32 market, bytes32 stream, bool isLong, bytes[] calldata reports)
        external
        returns (int256 pnl, bool busted)
    {
        LibGuard.enter();
        LibAccounts.requireOwner(id);
        uint256 price = LibOracle.verify(market, stream, reports).price1e18;
        uint256 bustBoundary = LibPnl.bustPrice(50_000e18, 100, 5e14, isLong);
        busted = LibPnl.isBusted(price, bustBoundary, isLong);
        if (busted) {
            pnl = -100e18;
        } else {
            (, pnl) = LibPnl.calculate(
                LibPnl.Position(50_000e18, price, 100e18, 100, isLong),
                LibPnl.Curve(0.02e18, 2e18, 1e18, 5e23, false)
            );
        }
        LibGuard.exit();
    }

    function threshold(bool isLong) external pure returns (uint256) {
        return LibPnl.bustPrice(50_000e18, 100, 5e14, isLong);
    }

    function quantize(uint256 amount, uint8 decimals) external pure returns (uint256) {
        return LibUnits.floorCash(amount, LibUnits.quantum(decimals));
    }
}

contract FoundationAcceptanceTest is Test {
    bytes32 internal constant MARKET = keccak256("fixture market");
    bytes32 internal constant STREAM = keccak256("fixture stream");
    StaticsAccountMock internal statics;
    ExecutionOracleMock internal oracle;
    BucketPerpsDiamond internal diamond;
    AccountFacet internal accounts;
    FoundationPreview internal preview;
    ActivityHarness internal activity;
    address internal alice;
    address internal bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        statics = new StaticsAccountMock();
        oracle = new ExecutionOracleMock();
        statics.mint(alice, 1);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](3);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = AccountFacet.accountState.selector;
        selectors[1] = AccountFacet.hasUnresolvedAccountState.selector;
        selectors[2] = AccountFacet.syncAccountActivity.selector;
        cuts[0] = IDiamondCut.FacetCut(address(new AccountFacet()), IDiamondCut.FacetCutAction.Add, selectors);
        selectors = new bytes4[](1);
        selectors[0] = ActivityHarness.setAccount.selector;
        cuts[1] =
            IDiamondCut.FacetCut(address(new ActivityHarness()), IDiamondCut.FacetCutAction.Add, selectors);
        selectors = new bytes4[](3);
        selectors[0] = FoundationPreview.preview.selector;
        selectors[1] = FoundationPreview.threshold.selector;
        selectors[2] = FoundationPreview.quantize.selector;
        cuts[2] =
            IDiamondCut.FacetCut(address(new FoundationPreview()), IDiamondCut.FacetCutAction.Add, selectors);
        diamond = new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap({
                governor: address(this),
                guardian: bob,
                upgradeDelay: 1 days,
                cuts: cuts,
                init: address(new AccountsInit()),
                data: abi.encodeCall(AccountsInit.initialize, (address(statics), address(statics)))
            })
        );
        statics.configure(address(diamond), true);
        accounts = AccountFacet(address(diamond));
        preview = FoundationPreview(address(diamond));
        activity = ActivityHarness(address(diamond));
        OracleInit oracleInit = new OracleInit();
        cuts = new IDiamondCut.FacetCut[](0);
        bytes memory data = abi.encodeCall(OracleInit.initialize, (address(oracle)));
        diamond.scheduleDiamondCut(cuts, address(oracleInit), data);
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(oracleInit), data);
        _price(50_000e18);
    }

    function test_TransferredAccountUsesNewOwnerWithIndependentReportSubmission() public {
        LibAccountsStorage.Account memory a;
        a.cashWad = 100e18;
        a.liveClaimCount = 1;
        a.unstakedRewardUnits = 17;
        vm.prank(alice);
        activity.setAccount(1, a);
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        _price(50_100e18);
        vm.prank(alice);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        preview.preview(1, MARKET, STREAM, true, new bytes[](0));
        assertEq(oracle.calls(), 0);
        vm.prank(bob);
        (int256 pnl, bool busted) = preview.preview(1, MARKET, STREAM, true, new bytes[](0));
        assertGt(pnl, 0);
        assertFalse(busted);
        assertEq(oracle.lastConsumer(), address(diamond));
        assertEq(accounts.accountState(1).cashWad, 100e18);
        assertEq(accounts.accountState(1).unstakedRewardUnits, 17);
        assertEq(statics.activeLegCount(1), 1);
        vm.prank(bob);
        vm.expectRevert();
        statics.close(1);
    }

    function test_ReferenceBoundaryIsInclusiveAtNormalizedPrecision() public {
        for (uint256 direction; direction < 2; ++direction) {
            bool isLong = direction == 0;
            uint256 boundary = preview.threshold(isLong);
            _price(boundary);
            vm.prank(alice);
            (int256 pnl, bool busted) = preview.preview(1, MARKET, STREAM, isLong, new bytes[](0));
            assertTrue(busted);
            assertEq(pnl, -100e18);
            _price(isLong ? boundary + 1 : boundary - 1);
            vm.prank(alice);
            (, busted) = preview.preview(1, MARKET, STREAM, isLong, new bytes[](0));
            assertFalse(busted);
        }
    }

    function test_SharedGuardCoversCallbacksAcrossDifferentFacets() public {
        oracle.setCallback(address(accounts), abi.encodeCall(AccountFacet.syncAccountActivity, (1)));
        vm.prank(alice);
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        preview.preview(1, MARKET, STREAM, true, new bytes[](0));
        assertEq(oracle.calls(), 0);
        assertEq(statics.activeLegCount(1), 0);
        assertFalse(accounts.accountState(1).externalStateActive);
    }

    function test_OracleFailureDoesNotGateAccountCleanupOrPureArithmetic() public {
        LibAccountsStorage.Account memory a;
        a.cashWad = 1;
        vm.prank(alice);
        activity.setAccount(1, a);
        oracle.setFailure(hex"deadbeef");
        a.cashWad = 0;
        vm.prank(alice);
        activity.setAccount(1, a);
        assertEq(statics.activeLegCount(1), 0);
        assertEq(preview.quantize(1234567890123456789, 6), 1234567000000000000);
        vm.prank(alice);
        statics.close(1);
    }

    function _price(uint256 price) private {
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(price, 100, 99, 101, STREAM));
    }
}
