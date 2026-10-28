// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StakingProtocolFixture } from "./StakingProtocolFixture.sol";
import { ControlFacet } from "../../src/facets/ControlFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";

abstract contract ControlProtocolFixture is StakingProtocolFixture {
    ControlFacet internal controls;

    function setUp() public virtual override {
        super.setUp();
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](3);
        s[0] = ControlFacet.pause.selector;
        s[1] = ControlFacet.unpause.selector;
        s[2] = ControlFacet.pausedGroups.selector;
        cuts[0] = _cut(address(new ControlFacet()), s);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        controls = ControlFacet(address(diamond));
    }
}
