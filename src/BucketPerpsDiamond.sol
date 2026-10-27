// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "./interfaces/IDiamondLoupe.sol";
import { LibDiamond } from "./libraries/LibDiamond.sol";
import { LibGuard } from "./libraries/LibGuard.sol";
import { LibProtocol } from "./libraries/LibProtocol.sol";

/// @notice Canonical entry point. Upgrade enforcement and loupe selectors cannot be replaced.
contract BucketPerpsDiamond is IDiamondCut, IDiamondLoupe, IERC165 {
    error UnknownSelector(bytes4 selector);
    error NativeCurrencyUnsupported();
    error OperationAlreadyScheduled();
    error OperationNotReady();

    event CutScheduled(bytes32 indexed operation, uint256 readyAt);
    event CutCancelled(bytes32 indexed operation);

    modifier guarded() {
        LibGuard.enter();
        _;
        LibGuard.exit();
    }

    struct Bootstrap {
        address governor;
        address guardian;
        uint64 upgradeDelay;
        FacetCut[] cuts;
        address init;
        bytes data;
    }

    constructor(Bootstrap memory bootstrap) {
        LibProtocol.initialize(bootstrap.governor, bootstrap.guardian, bootstrap.upgradeDelay);
        LibDiamond.registerImmutable(BucketPerpsDiamond.diamondCut.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.scheduleDiamondCut.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.cancelDiamondCut.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.facets.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.facetFunctionSelectors.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.facetAddresses.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.facetAddress.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.supportsInterface.selector);
        LibDiamond.registerImmutable(BucketPerpsDiamond.protocolState.selector);
        LibGuard.enter();
        LibDiamond.cut(bootstrap.cuts, bootstrap.init, bootstrap.data);
        LibGuard.exit();
    }

    function protocolState() external view returns (address, address, uint64, bool) {
        LibProtocol.State storage p = LibProtocol.state();
        return (p.governor, p.guardian, p.upgradeDelay, p.finalized);
    }

    function scheduleDiamondCut(FacetCut[] calldata cuts, address init, bytes calldata data)
        external
        guarded
        returns (bytes32 operation)
    {
        LibProtocol.requireGovernor();
        LibProtocol.requireUpgradeable();
        operation = keccak256(abi.encode(cuts, init, data));
        LibProtocol.State storage p = LibProtocol.state();
        if (p.pendingCuts[operation] != 0) revert OperationAlreadyScheduled();
        uint256 readyAt = block.timestamp + p.upgradeDelay;
        p.pendingCuts[operation] = readyAt;
        emit CutScheduled(operation, readyAt);
    }

    function cancelDiamondCut(bytes32 operation) external guarded {
        LibProtocol.requireGovernor();
        delete LibProtocol.state().pendingCuts[operation];
        emit CutCancelled(operation);
    }

    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external guarded {
        LibProtocol.requireGovernor();
        LibProtocol.requireUpgradeable();
        bytes32 operation = keccak256(abi.encode(cuts, init, data));
        LibProtocol.State storage p = LibProtocol.state();
        uint256 readyAt = p.pendingCuts[operation];
        if (readyAt == 0 || block.timestamp < readyAt) revert OperationNotReady();
        delete p.pendingCuts[operation];
        LibDiamond.cut(cuts, init, data);
    }

    function facets() external view returns (Facet[] memory result) {
        LibDiamond.State storage s = LibDiamond.state();
        result = new Facet[](s.addresses.length);
        for (uint256 i; i < result.length; ++i) {
            address facet = s.addresses[i];
            result[i] = Facet(facet, s.facetSelectors[facet]);
        }
    }

    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory) {
        return LibDiamond.state().facetSelectors[facet];
    }

    function facetAddresses() external view returns (address[] memory) {
        return LibDiamond.state().addresses;
    }

    function facetAddress(bytes4 selector) external view returns (address) {
        return LibDiamond.state().selectors[selector].facet;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IDiamondCut).interfaceId
            || interfaceId == type(IDiamondLoupe).interfaceId;
    }

    fallback() external payable {
        if (msg.value != 0) revert NativeCurrencyUnsupported();
        address facet = LibDiamond.state().selectors[msg.sig].facet;
        if (facet == address(0)) revert UnknownSelector(msg.sig);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {
        revert NativeCurrencyUnsupported();
    }
}
