// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { QueueHarness } from "./Fifo.t.sol";
import { LibSettlement } from "../../src/libraries/LibSettlement.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";

contract EntitlementHarness is QueueHarness {
    constructor(address nft, address token) QueueHarness(nft, token) { }

    function entitle(uint256 id, uint256 amount) external returns (LibSettlement.Payout memory result) {
        LibGuard.enter();
        result = LibSettlement.payout(id, amount);
        LibGuard.exit();
    }

    function seedHouse(uint256 amount) external {
        LibBookStorage.state().custodyWad += amount;
    }
}

contract EntitlementTest is Test {
    EntitlementHarness internal engine;
    CashTokenMock internal token;

    function setUp() public {
        StaticsAccountMock nft = new StaticsAccountMock();
        nft.mint(address(this), 1);
        nft.mint(address(this), 2);
        token = new CashTokenMock(6);
        engine = new EntitlementHarness(address(nft), address(token));
        nft.configure(address(engine), true);
    }

    function test_NoHouseQueuesWholeEntitlementWithoutCreatingCash() public {
        LibSettlement.Payout memory result = engine.entitle(1, 100e18);
        assertEq(result.paidWad, 0);
        assertEq(result.queuedWad, 100e18);
        assertEq(engine.book().queuedDebtWad, 100e18);
        assertEq(engine.book().custodyWad, 0);
        assertEq(engine.book().accountCashWad, 0);
    }

    function test_PartialHouseFundingQueuesOnlyUnpaidRemainder() public {
        _fund(60e18);
        LibSettlement.Payout memory result = engine.entitle(1, 100e18);
        assertEq(result.paidWad, 60e18);
        assertEq(result.queuedWad, 40e18);
        assertEq(engine.book().custodyWad, 60e18);
        assertEq(engine.accountState(1).cashWad, 60e18);
        assertEq(engine.claimState(result.claimId).remainingWad, 40e18);
    }

    function test_OlderFifoBlocksDirectFundingEvenWithHouseCash() public {
        uint256 old = engine.seedEntitlement(2, 10e18);
        _fund(100e18);
        LibSettlement.Payout memory result = engine.entitle(1, 20e18);
        assertEq(result.paidWad, 0);
        assertEq(result.queuedWad, 20e18);
        assertGt(result.claimId, old);
        assertEq(engine.book().accountCashWad, 0);
        assertEq(engine.harvest(1), 10e18);
        assertEq(engine.accountState(1).cashWad, 0);
        assertEq(engine.accountState(2).cashWad, 10e18);
    }

    function test_ZeroEntitlementDoesNotCreateClaimOrAccountLeg() public {
        LibSettlement.Payout memory result = engine.entitle(1, 0);
        assertEq(result.claimId, 0);
        assertEq(engine.accountState(1).liveClaimCount, 0);
        assertFalse(engine.accountState(1).externalStateActive);
    }

    function _fund(uint256 amount) private {
        token.mint(address(engine), amount / 1e12);
        engine.seedHouse(amount);
    }
}
