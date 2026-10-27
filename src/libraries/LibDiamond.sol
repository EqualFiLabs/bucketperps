// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IDiamondCut } from "../interfaces/IDiamondCut.sol";
import { LibProtocol } from "./LibProtocol.sol";

library LibDiamond {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.diamond.v1");

    struct Selector {
        address facet;
        uint256 position;
    }

    struct State {
        mapping(bytes4 selector => Selector route) selectors;
        mapping(address facet => bytes4[] selectors) facetSelectors;
        mapping(address facet => uint256 position) facetPositions;
        address[] addresses;
    }

    error EmptySelectors();
    error InvalidFacet(address facet);
    error SelectorExists(bytes4 selector);
    error SelectorMissing(bytes4 selector);
    error ImmutableSelector(bytes4 selector);
    error SameFacet(bytes4 selector);
    error InvalidRemoval();
    error InvalidInitializer();
    error InitializerAlreadyUsed();

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }

    function registerImmutable(bytes4 selector) internal {
        _add(selector, address(this));
    }

    function cut(IDiamondCut.FacetCut[] memory cuts, address init, bytes memory data) internal {
        LibProtocol.requireUpgradeable();
        for (uint256 i; i < cuts.length; ++i) {
            IDiamondCut.FacetCut memory item = cuts[i];
            if (item.functionSelectors.length == 0) revert EmptySelectors();
            if (item.action == IDiamondCut.FacetCutAction.Remove) {
                if (item.facetAddress != address(0)) revert InvalidRemoval();
            } else if (item.facetAddress == address(this) || item.facetAddress.code.length == 0) {
                revert InvalidFacet(item.facetAddress);
            }
            for (uint256 j; j < item.functionSelectors.length; ++j) {
                bytes4 selector = item.functionSelectors[j];
                address oldFacet = state().selectors[selector].facet;
                if (oldFacet == address(this)) revert ImmutableSelector(selector);
                if (item.action == IDiamondCut.FacetCutAction.Add) {
                    if (oldFacet != address(0)) revert SelectorExists(selector);
                    _add(selector, item.facetAddress);
                } else {
                    if (oldFacet == address(0)) revert SelectorMissing(selector);
                    if (oldFacet == item.facetAddress) revert SameFacet(selector);
                    _remove(selector, oldFacet);
                    if (item.action == IDiamondCut.FacetCutAction.Replace) _add(selector, item.facetAddress);
                }
            }
        }
        emit IDiamondCut.DiamondCut(cuts, init, data);
        _initialize(init, data);
    }

    function _add(bytes4 selector, address facet) private {
        State storage s = state();
        bytes4[] storage selectors = s.facetSelectors[facet];
        if (selectors.length == 0) {
            s.facetPositions[facet] = s.addresses.length;
            s.addresses.push(facet);
        }
        s.selectors[selector] = Selector(facet, selectors.length);
        selectors.push(selector);
    }

    function _remove(bytes4 selector, address facet) private {
        State storage s = state();
        bytes4[] storage selectors = s.facetSelectors[facet];
        uint256 position = s.selectors[selector].position;
        bytes4 lastSelector = selectors[selectors.length - 1];
        selectors[position] = lastSelector;
        s.selectors[lastSelector].position = position;
        selectors.pop();
        delete s.selectors[selector];
        if (selectors.length == 0) {
            uint256 facetPosition = s.facetPositions[facet];
            address lastFacet = s.addresses[s.addresses.length - 1];
            s.addresses[facetPosition] = lastFacet;
            s.facetPositions[lastFacet] = facetPosition;
            s.addresses.pop();
            delete s.facetPositions[facet];
        }
    }

    function _initialize(address init, bytes memory data) private {
        if (init == address(0)) {
            if (data.length != 0) revert InvalidInitializer();
            return;
        }
        if (init == address(this) || init.code.length == 0 || data.length < 4) revert InvalidInitializer();
        LibProtocol.State storage p = LibProtocol.state();
        if (p.initializing || p.usedInitializers[init]) revert InitializerAlreadyUsed();
        p.usedInitializers[init] = true;
        p.initializing = true;
        (bool success, bytes memory result) = init.delegatecall(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        p.initializing = false;
    }
}
