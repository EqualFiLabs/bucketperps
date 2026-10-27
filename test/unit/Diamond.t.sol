// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "../../src/interfaces/IDiamondLoupe.sol";
import { LibDiamond } from "../../src/libraries/LibDiamond.sol";
import { LibProtocol } from "../../src/libraries/LibProtocol.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";

contract StateFacet {
    function write(uint256 positionId, uint256 cash, uint256 custody) external {
        LibGuard.enter();
        LibAccountsStorage.state().accounts[positionId].cashWad = cash;
        LibBookStorage.state().custodyWad = custody;
        LibGuard.exit();
    }

    function read(uint256 positionId) external view returns (uint256, uint256, address, address) {
        return (
            LibAccountsStorage.state().accounts[positionId].cashWad,
            LibBookStorage.state().custodyWad,
            address(this),
            msg.sender
        );
    }

    function reenter() external {
        LibGuard.enter();
        StateFacet(address(this)).write(1, 99, 99);
        LibGuard.exit();
    }
}

contract ReplacementFacet {
    function read(uint256) external view returns (uint256, uint256, address, address) {
        return (7, 8, address(this), msg.sender);
    }
}

contract FinalizationHarness {
    function finalizeForTest() external {
        LibProtocol.requireGovernor();
        LibProtocol.state().finalized = true;
    }

    function initializeAgain() external {
        LibProtocol.initialize(msg.sender, msg.sender, 1);
    }
}

contract Initializer {
    error NotInitializing();

    function initialize(uint256 custody) external {
        if (!LibProtocol.state().initializing) revert NotInitializing();
        LibBookStorage.state().custodyWad = custody;
    }
}

contract RevertingInitializer {
    error InitializationFailed();

    function initialize() external {
        LibBookStorage.state().custodyWad = 999;
        revert InitializationFailed();
    }
}

contract ReentrantInitializer {
    function initialize() external {
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        BucketPerpsDiamond(payable(address(this))).scheduleDiamondCut(empty, address(0), "");
    }
}

contract DiamondTest is Test {
    BucketPerpsDiamond internal diamond;
    StateFacet internal stateFacet;
    address internal governor;
    address internal guardian;
    uint64 internal constant DELAY = 1 days; // Fixture only.

    function setUp() public {
        governor = makeAddr("governor");
        guardian = makeAddr("guardian");
        stateFacet = new StateFacet();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = StateFacet.write.selector;
        selectors[1] = StateFacet.read.selector;
        selectors[2] = StateFacet.reenter.selector;
        diamond =
            _deploy(_cut(address(stateFacet), IDiamondCut.FacetCutAction.Add, selectors), address(0), "");
    }

    function testFuzz_RoutingPreservesContextAndIsolatesStorage(
        uint256 positionId,
        uint256 cash,
        uint256 custody
    ) public {
        StateFacet(address(diamond)).write(positionId, cash, custody);
        (uint256 actualCash, uint256 actualCustody, address executionAddress, address caller) =
            StateFacet(address(diamond)).read(positionId);
        assertEq(actualCash, cash);
        assertEq(actualCustody, custody);
        assertEq(executionAddress, address(diamond));
        assertEq(caller, address(this));
        (address actualGovernor, address actualGuardian, uint64 delay, bool finalized) =
            diamond.protocolState();
        assertEq(actualGovernor, governor);
        assertEq(actualGuardian, guardian);
        assertEq(delay, DELAY);
        assertFalse(finalized);
        (actualCash, actualCustody,,) = stateFacet.read(positionId);
        assertEq(actualCash, 0);
        assertEq(actualCustody, 0);
        assertEq(diamond.facetAddress(StateFacet.write.selector), address(stateFacet));
    }

    function test_UnknownSelectorAndNativeValueFail() public {
        vm.expectRevert(
            abi.encodeWithSelector(BucketPerpsDiamond.UnknownSelector.selector, bytes4(0x12345678))
        );
        (bool success,) = address(diamond).call(hex"12345678");
        assertTrue(success); // expectRevert consumes the expected failed call.
        vm.deal(address(this), 1);
        vm.expectRevert(BucketPerpsDiamond.NativeCurrencyUnsupported.selector);
        (success,) = address(diamond).call{ value: 1 }("");
        assertTrue(success);
    }

    function test_UnauthorizedSchedulingAndCutsFail() public {
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](0);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        diamond.diamondCut(cuts, address(0), "");
        vm.prank(guardian);
        vm.expectRevert(LibProtocol.Unauthorized.selector);
        diamond.scheduleDiamondCut(cuts, address(0), "");
    }

    function test_CutsRequireExactScheduledPayloadAndDelay() public {
        ReplacementFacet replacement = new ReplacementFacet();
        IDiamondCut.FacetCut[] memory cuts =
            _single(address(replacement), IDiamondCut.FacetCutAction.Replace, StateFacet.read.selector);
        vm.startPrank(governor);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.expectRevert(BucketPerpsDiamond.OperationNotReady.selector);
        diamond.diamondCut(cuts, address(0), "");
        vm.warp(vm.getBlockTimestamp() + DELAY - 1);
        vm.expectRevert(BucketPerpsDiamond.OperationNotReady.selector);
        diamond.diamondCut(cuts, address(0), "");
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.expectRevert(BucketPerpsDiamond.OperationNotReady.selector);
        diamond.diamondCut(cuts, address(0), hex"01");
        diamond.diamondCut(cuts, address(0), "");
        vm.expectRevert(BucketPerpsDiamond.OperationNotReady.selector);
        diamond.diamondCut(cuts, address(0), "");
        vm.stopPrank();
        (uint256 result,,,) = StateFacet(address(diamond)).read(1);
        assertEq(result, 7);
        assertEq(diamond.facetAddress(StateFacet.read.selector), address(replacement));
        _assertLoupeConsistent();
    }

    function test_CancellationAndDuplicateSchedule() public {
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](0);
        vm.startPrank(governor);
        bytes32 operation = diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.expectRevert(BucketPerpsDiamond.OperationAlreadyScheduled.selector);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        diamond.cancelDiamondCut(operation);
        vm.warp(vm.getBlockTimestamp() + DELAY);
        vm.expectRevert(BucketPerpsDiamond.OperationNotReady.selector);
        diamond.diamondCut(cuts, address(0), "");
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    function test_ImmutableSelectorsCannotBeAddedReplacedOrRemoved() public {
        for (uint256 action; action < 3; ++action) {
            IDiamondCut.FacetCut[] memory cuts = _single(
                action == 2 ? address(0) : address(stateFacet),
                IDiamondCut.FacetCutAction(action),
                BucketPerpsDiamond.diamondCut.selector
            );
            _schedule(cuts, address(0), "");
            vm.prank(governor);
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibDiamond.ImmutableSelector.selector, BucketPerpsDiamond.diamondCut.selector
                )
            );
            diamond.diamondCut(cuts, address(0), "");
        }
    }

    function test_CollisionsMissingSelectorsAndInvalidTargetsFail() public {
        _expectCutFailure(
            _single(address(stateFacet), IDiamondCut.FacetCutAction.Add, StateFacet.read.selector),
            abi.encodeWithSelector(LibDiamond.SelectorExists.selector, StateFacet.read.selector)
        );
        _expectCutFailure(
            _single(address(stateFacet), IDiamondCut.FacetCutAction.Replace, StateFacet.read.selector),
            abi.encodeWithSelector(LibDiamond.SameFacet.selector, StateFacet.read.selector)
        );
        _expectCutFailure(
            _single(address(0), IDiamondCut.FacetCutAction.Remove, bytes4(0x12345678)),
            abi.encodeWithSelector(LibDiamond.SelectorMissing.selector, bytes4(0x12345678))
        );
        _expectCutFailure(
            _single(governor, IDiamondCut.FacetCutAction.Add, bytes4(0x12345678)),
            abi.encodeWithSelector(LibDiamond.InvalidFacet.selector, governor)
        );
        _expectCutFailure(
            _single(address(stateFacet), IDiamondCut.FacetCutAction.Remove, StateFacet.read.selector),
            abi.encodeWithSelector(LibDiamond.InvalidRemoval.selector)
        );
    }

    function test_RemoveAllFacetSelectorsMaintainsLoupeIndexes() public {
        bytes4[] memory selectors = diamond.facetFunctionSelectors(address(stateFacet));
        IDiamondCut.FacetCut[] memory cuts = _cut(address(0), IDiamondCut.FacetCutAction.Remove, selectors);
        _execute(cuts, address(0), "");
        assertEq(diamond.facetAddresses().length, 1);
        assertEq(diamond.facetFunctionSelectors(address(stateFacet)).length, 0);
        assertEq(diamond.facetAddress(StateFacet.write.selector), address(0));
        _assertLoupeConsistent();
        _execute(_cut(address(stateFacet), IDiamondCut.FacetCutAction.Add, selectors), address(0), "");
        _assertLoupeConsistent();
        StateFacet(address(diamond)).write(1, 12, 34);
        (uint256 cash, uint256 custody,,) = StateFacet(address(diamond)).read(1);
        assertEq(cash, 12);
        assertEq(custody, 34);
    }

    function test_InitializerRunsInDiamondAndCannotRunTwice() public {
        Initializer init = new Initializer();
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](0);
        bytes memory data = abi.encodeCall(Initializer.initialize, (42));
        _execute(cuts, address(init), data);
        (, uint256 custody,,) = StateFacet(address(diamond)).read(1);
        assertEq(custody, 42);
        _schedule(cuts, address(init), abi.encodeCall(Initializer.initialize, (99)));
        vm.prank(governor);
        vm.expectRevert(LibDiamond.InitializerAlreadyUsed.selector);
        diamond.diamondCut(cuts, address(init), abi.encodeCall(Initializer.initialize, (99)));
        (, custody,,) = StateFacet(address(diamond)).read(1);
        assertEq(custody, 42);
    }

    function test_FailedInitializerRollsBackRoutingAndState() public {
        StateFacet(address(diamond)).write(1, 11, 22);
        RevertingInitializer init = new RevertingInitializer();
        ReplacementFacet replacement = new ReplacementFacet();
        IDiamondCut.FacetCut[] memory cuts =
            _single(address(replacement), IDiamondCut.FacetCutAction.Replace, StateFacet.read.selector);
        bytes memory data = abi.encodeCall(RevertingInitializer.initialize, ());
        _schedule(cuts, address(init), data);
        vm.prank(governor);
        vm.expectRevert(RevertingInitializer.InitializationFailed.selector);
        diamond.diamondCut(cuts, address(init), data);
        assertEq(diamond.facetAddress(StateFacet.read.selector), address(stateFacet));
        (uint256 cash, uint256 custody,,) = StateFacet(address(diamond)).read(1);
        assertEq(cash, 11);
        assertEq(custody, 22);
        _assertLoupeConsistent();
    }

    function test_InvalidAndReentrantInitializersAreRejected() public {
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        _schedule(empty, address(0), hex"12345678");
        vm.prank(governor);
        vm.expectRevert(LibDiamond.InvalidInitializer.selector);
        diamond.diamondCut(empty, address(0), hex"12345678");
        _schedule(empty, address(diamond), hex"12345678");
        vm.prank(governor);
        vm.expectRevert(LibDiamond.InvalidInitializer.selector);
        diamond.diamondCut(empty, address(diamond), hex"12345678");
        ReentrantInitializer init = new ReentrantInitializer();
        bytes memory data = abi.encodeCall(ReentrantInitializer.initialize, ());
        _schedule(empty, address(init), data);
        vm.prank(governor);
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        diamond.diamondCut(empty, address(init), data);
        // Reverted initialization must not leave the shared lock engaged.
        StateFacet(address(diamond)).write(1, 23, 45);
        (uint256 cash, uint256 custody,,) = StateFacet(address(diamond)).read(1);
        assertEq(cash, 23);
        assertEq(custody, 45);
    }

    function test_BatchCollisionRollsBackEarlierRoutingChanges() public {
        bytes4 extra = bytes4(0x12345678);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = extra;
        selectors[1] = StateFacet.write.selector;
        _expectCutFailure(
            _cut(address(stateFacet), IDiamondCut.FacetCutAction.Add, selectors),
            abi.encodeWithSelector(LibDiamond.SelectorExists.selector, StateFacet.write.selector)
        );
        assertEq(diamond.facetAddress(extra), address(0));
        assertEq(diamond.facetFunctionSelectors(address(stateFacet)).length, 3);
        _assertLoupeConsistent();
    }

    function test_SharedReentrancyBoundaryRevertsWithoutChangingState() public {
        StateFacet(address(diamond)).write(1, 11, 22);
        vm.expectRevert(LibGuard.ReentrantCall.selector);
        StateFacet(address(diamond)).reenter();
        StateFacet(address(diamond)).write(1, 33, 44);
        (uint256 cash, uint256 custody,,) = StateFacet(address(diamond)).read(1);
        assertEq(cash, 33);
        assertEq(custody, 44);
    }

    function test_FinalizedBitBlocksPreviouslyScheduledAndFutureCuts() public {
        FinalizationHarness harness = new FinalizationHarness();
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = FinalizationHarness.finalizeForTest.selector;
        selectors[1] = FinalizationHarness.initializeAgain.selector;
        _execute(_cut(address(harness), IDiamondCut.FacetCutAction.Add, selectors), address(0), "");
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        _schedule(empty, address(0), "");
        vm.startPrank(governor);
        vm.expectRevert(LibProtocol.AlreadyInitialized.selector);
        FinalizationHarness(address(diamond)).initializeAgain();
        FinalizationHarness(address(diamond)).finalizeForTest();
        vm.expectRevert(LibProtocol.ProtocolFinalized.selector);
        diamond.diamondCut(empty, address(0), "");
        vm.expectRevert(LibProtocol.ProtocolFinalized.selector);
        diamond.scheduleDiamondCut(empty, address(0), "");
        vm.stopPrank();
    }

    function test_ZeroUpgradeDelayAllowsScheduledCutInSameBlock() public {
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        BucketPerpsDiamond immediate = new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap(governor, guardian, 0, empty, address(0), "")
        );
        IDiamondCut.FacetCut[] memory cuts =
            _single(address(stateFacet), IDiamondCut.FacetCutAction.Add, StateFacet.write.selector);
        vm.startPrank(governor);
        immediate.scheduleDiamondCut(cuts, address(0), "");
        immediate.diamondCut(cuts, address(0), "");
        vm.stopPrank();
        StateFacet(address(immediate)).write(1, 11, 22);
        assertEq(immediate.facetAddress(StateFacet.write.selector), address(stateFacet));
    }

    function test_BootstrapRejectsInvalidAuthorityAndImmutableCollision() public {
        IDiamondCut.FacetCut[] memory empty = new IDiamondCut.FacetCut[](0);
        vm.expectRevert(LibProtocol.InvalidAuthority.selector);
        new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap(address(0), guardian, DELAY, empty, address(0), "")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.ImmutableSelector.selector, BucketPerpsDiamond.diamondCut.selector
            )
        );
        _deploy(
            _single(
                address(stateFacet), IDiamondCut.FacetCutAction.Add, BucketPerpsDiamond.diamondCut.selector
            ),
            address(0),
            ""
        );
    }

    function _assertLoupeConsistent() internal view {
        IDiamondLoupe.Facet[] memory all = diamond.facets();
        address[] memory addresses = diamond.facetAddresses();
        assertEq(all.length, addresses.length);
        for (uint256 i; i < all.length; ++i) {
            assertEq(all[i].facetAddress, addresses[i]);
            assertGt(all[i].functionSelectors.length, 0);
            for (uint256 j; j < all[i].functionSelectors.length; ++j) {
                assertEq(diamond.facetAddress(all[i].functionSelectors[j]), addresses[i]);
                for (uint256 k; k < i; ++k) {
                    assertTrue(addresses[k] != addresses[i]);
                }
            }
        }
    }

    function _deploy(IDiamondCut.FacetCut[] memory cuts, address init, bytes memory data)
        internal
        returns (BucketPerpsDiamond)
    {
        return new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap(governor, guardian, DELAY, cuts, init, data)
        );
    }

    function _single(address facet, IDiamondCut.FacetCutAction action, bytes4 selector)
        internal
        pure
        returns (IDiamondCut.FacetCut[] memory)
    {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        return _cut(facet, action, selectors);
    }

    function _cut(address facet, IDiamondCut.FacetCutAction action, bytes4[] memory selectors)
        internal
        pure
        returns (IDiamondCut.FacetCut[] memory cuts)
    {
        cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut(facet, action, selectors);
    }

    function _schedule(IDiamondCut.FacetCut[] memory cuts, address init, bytes memory data) internal {
        vm.prank(governor);
        diamond.scheduleDiamondCut(cuts, init, data);
        vm.warp(vm.getBlockTimestamp() + DELAY);
    }

    function _execute(IDiamondCut.FacetCut[] memory cuts, address init, bytes memory data) internal {
        _schedule(cuts, init, data);
        vm.prank(governor);
        diamond.diamondCut(cuts, init, data);
    }

    function _expectCutFailure(IDiamondCut.FacetCut[] memory cuts, bytes memory errorData) internal {
        _schedule(cuts, address(0), "");
        vm.prank(governor);
        vm.expectRevert(errorData);
        diamond.diamondCut(cuts, address(0), "");
    }
}
