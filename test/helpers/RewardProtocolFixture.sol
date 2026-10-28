// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ProtocolFixture } from "./ProtocolFixture.sol";
import { RewardFacet } from "../../src/facets/RewardFacet.sol";
import { RewardsInit } from "../../src/init/RewardsInit.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";

abstract contract RewardProtocolFixture is ProtocolFixture {
    CashTokenMock internal staticsToken;
    RewardFacet internal rewards;

    function setUp() public virtual override {
        super.setUp();
        staticsToken = new CashTokenMock(18);
        rewards = RewardFacet(address(diamond));
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](5);
        s[0] = RewardFacet.rewardState.selector;
        s[1] = RewardFacet.fundRewardInventory.selector;
        s[2] = RewardFacet.wrap.selector;
        s[3] = RewardFacet.unwrap.selector;
        s[4] = RewardFacet.setLossRewardRate.selector;
        cuts[0] = _cut(address(new RewardFacet()), s);
        address init = address(new RewardsInit());
        bytes memory data = abi.encodeCall(RewardsInit.initialize, (address(staticsToken)));
        diamond.scheduleDiamondCut(cuts, init, data);
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, init, data);
    }

    function _inventory(uint256 units) internal {
        staticsToken.mint(address(this), units);
        staticsToken.approve(address(diamond), units);
        rewards.fundRewardInventory(units);
    }
}
