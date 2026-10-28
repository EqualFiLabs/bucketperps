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
        bytes4[] memory s = new bytes4[](10);
        s[0] = ControlFacet.pause.selector;
        s[1] = ControlFacet.unpause.selector;
        s[2] = ControlFacet.pausedGroups.selector;
        s[3] = ControlFacet.safetyAction.selector;
        s[4] = ControlFacet.safetyDelay.selector;
        s[5] = ControlFacet.setSafetyDelays.selector;
        s[6] = ControlFacet.scheduleSafetyAction.selector;
        s[7] = ControlFacet.cancelSafetyAction.selector;
        s[8] = ControlFacet.executeOracle.selector;
        s[9] = ControlFacet.executeOperatorRouter.selector;
        cuts[0] = _cut(address(new ControlFacet()), s);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        controls = ControlFacet(address(diamond));
    }
}
