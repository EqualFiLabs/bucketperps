// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { RewardProtocolFixture } from "./RewardProtocolFixture.sol";
import { StakingFacet } from "../../src/facets/StakingFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";

abstract contract StakingProtocolFixture is RewardProtocolFixture {
    StakingFacet internal staking;

    function setUp() public virtual override {
        super.setUp();
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](5);
        s[0] = StakingFacet.stake.selector;
        s[1] = StakingFacet.unstake.selector;
        s[2] = StakingFacet.claimStakerRevenue.selector;
        s[3] = StakingFacet.pendingStakerRevenue.selector;
        s[4] = StakingFacet.stakingTotals.selector;
        cuts[0] = _cut(address(new StakingFacet()), s);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        staking = StakingFacet(address(diamond));
    }

    function _earnReceipts(uint256 id, address owner) internal {
        _inventory(1000e18);
        rewards.setLossRewardRate(1e18);
        uint256 trade = _openCash(id, owner, true);
        _price(49_900e18);
        vm.prank(owner);
        settlement.closePosition(id, trade, block.timestamp, new bytes[](0));
        _price(50_000e18);
    }
}
