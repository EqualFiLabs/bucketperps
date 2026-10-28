// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { DollarProtocolFixture } from "../helpers/DollarProtocolFixture.sol";
import { ViewFacet } from "../../src/facets/ViewFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { LibTrades } from "../../src/libraries/LibTrades.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";

contract ViewsTest is DollarProtocolFixture {
    ViewFacet internal views;

    function setUp() public override {
        super.setUp();
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](6);
        s[0] = ViewFacet.ledgerState.selector;
        s[1] = ViewFacet.accountOverview.selector;
        s[2] = ViewFacet.externalAccountIdentity.selector;
        s[3] = ViewFacet.accountTradeIds.selector;
        s[4] = ViewFacet.tradeContext.selector;
        s[5] = ViewFacet.rewardBacking.selector;
        cuts[0] = _cut(address(new ViewFacet()), s);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        views = ViewFacet(address(diamond));
    }

    function testBoundedHistoricalTradeDiscoveryPreservesTermsAndCurrentStream() public {
        uint256 first = _openCash(1, alice, true);
        _openCash(2, bob, false);
        uint256 second = _openCash(1, alice, false);
        (uint256[] memory ids, uint256 next) = views.accountTradeIds(1, 0, 1);
        assertEq(ids.length, 1);
        assertEq(ids[0], first);
        assertEq(next, 1);
        (ids, next) = views.accountTradeIds(1, next, 64);
        assertEq(ids[0], second);
        assertEq(next, 2);
        vm.expectRevert();
        views.accountTradeIds(1, 0, 65);
        bytes32 replacement = keccak256("new stream");
        markets.configureMarket(MARKET, replacement, _risk());
        (LibTrades.Trade memory trade, LibMarkets.Terms memory terms, bytes32 current,) =
            views.tradeContext(first);
        assertEq(trade.streamId, STREAM);
        assertEq(current, replacement);
        assertEq(terms.fees.winStakerBps, 100);
    }

    function testBackingAndLedgerViewsReconcileEconomicOwnership() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 20e18);
        (uint256 inventory, uint256 backing, uint256 supply, uint256 actualInventory, uint256 actualBacking) =
            views.rewardBacking();
        assertEq(inventory, actualInventory);
        assertEq(backing, actualBacking);
        assertEq(supply, backing);
        ViewFacet.LedgerView memory v = views.ledgerState();
        assertEq(
            v.book.custodyWad,
            v.book.accountCashWad + v.book.lockedCashMarginWad + v.book.fundedPayablesWad + v.houseCashWad
        );
        (bytes32 kind, bytes32 localId, bool active) = views.externalAccountIdentity(1);
        assertEq(kind, keccak256("bucketperps.account.v1"));
        assertEq(localId, bytes32(uint256(1)));
        assertTrue(active);
    }
}
