// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ControlProtocolFixture } from "./ControlProtocolFixture.sol";
import { SettlementAssetFacet } from "../../src/facets/SettlementAssetFacet.sol";
import { DollarCoreMock } from "../mocks/DollarCoreMock.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";

abstract contract DollarProtocolFixture is ControlProtocolFixture {
    SettlementAssetFacet internal assetFacet;
    DollarCoreMock internal dollarCore;
    CashTokenMock internal dollar;

    function setUp() public virtual override {
        super.setUp();
        dollar = new CashTokenMock(18);
        dollarCore = new DollarCoreMock(token, dollar);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory s = new bytes4[](3);
        s[0] = SettlementAssetFacet.dollarMigrationState.selector;
        s[1] = SettlementAssetFacet.configureDollarMigration.selector;
        s[2] = SettlementAssetFacet.migrateUsdGToUsdStx.selector;
        cuts[0] = _cut(address(new SettlementAssetFacet()), s);
        diamond.scheduleDiamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 1 days);
        diamond.diamondCut(cuts, address(0), "");
        assetFacet = SettlementAssetFacet(address(diamond));
    }

    function _bindDollar() internal {
        controls.scheduleSafetyAction(
            keccak256(abi.encode("dollar-binding", address(dollarCore), address(dollar), uint256(1)))
        );
        assetFacet.configureDollarMigration(address(dollarCore), address(dollar), 1);
    }

    function _migrate() internal {
        controls.scheduleSafetyAction(
            keccak256(abi.encode("dollar-migration", address(dollarCore), address(dollar), uint256(1)))
        );
        assetFacet.migrateUsdGToUsdStx();
    }
}
