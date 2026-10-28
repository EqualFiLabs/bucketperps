// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StakingProtocolFixture } from "../helpers/StakingProtocolFixture.sol";
import { FeeFacet } from "../../src/facets/FeeFacet.sol";
import { OperatorRouterInit } from "../../src/init/OperatorRouterInit.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RouterFixture {
    bool public reject;

    function fail(bool value) external {
        reject = value;
    }

    function addRewards(address asset, uint256 units) external {
        require(!reject, "router rejected");
        IERC20(asset).transferFrom(msg.sender, address(this), units);
    }
}

contract OperatorDeliveryTest is StakingProtocolFixture {
    RouterFixture internal router;

    function setUp() public override {
        super.setUp();
        router = new RouterFixture();
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](1);
        s[0] = FeeFacet.flushOperatorFees.selector;
        cuts[0] = _cut(address(new FeeFacet()), s);
        address init = address(new OperatorRouterInit());
        bytes memory data = abi.encodeCall(OperatorRouterInit.initialize, (address(router)));
        diamond.scheduleDiamondCut(cuts, init, data);
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, init, data);
    }

    function testRouterFailurePreservesPayableAndSettlementContinues() public {
        router.fail(true);
        _earnReceipts(1, alice);
        assertEq(feeFacet.feePayables().operatorPayableWad, 0.04e18);
        uint256 beforeF = bookView.book().fundedPayablesWad;
        vm.expectRevert();
        feeFacet.flushOperatorFees(0.04e18);
        assertEq(feeFacet.feePayables().operatorPayableWad, 0.04e18);
        assertEq(bookView.book().fundedPayablesWad, beforeF);
        _earnReceipts(2, bob);
        router.fail(false);
        uint256 beforeT = bookView.book().custodyWad;
        feeFacet.flushOperatorFees(0.08e18);
        assertEq(token.balanceOf(address(router)), 80_000);
        assertEq(token.allowance(address(diamond), address(router)), 0);
        assertEq(bookView.book().custodyWad, beforeT - 0.08e18);
        assertEq(feeFacet.feePayables().operatorPayableWad, 0);
    }
}
