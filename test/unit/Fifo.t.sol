// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { CashHarness } from "./Cash.t.sol";
import { Test } from "forge-std/Test.sol";
import { QueueFacet } from "../../src/facets/QueueFacet.sol";
import { LibQueue } from "../../src/libraries/LibQueue.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";

contract QueueHarness is CashHarness, QueueFacet {
    constructor(address nft, address token) CashHarness(nft, token) { }

    function seedEntitlement(uint256 id, uint256 amount) external returns (uint256 claimId) {
        LibGuard.enter();
        LibBookStorage.state().realizedHousePnlWad -= int256(amount);
        claimId = LibQueue.enqueue(id, amount);
        LibGuard.exit();
    }

    // Fixture for already-committed entries; real bounded consumption follows separately.
    function tombstone(uint256 id) external {
        LibQueue.Claim storage c = LibQueue.state().claims[id];
        LibBookStorage.State storage b = LibBookStorage.state();
        uint256 amount = c.remainingWad;
        c.remainingWad = 0;
        b.queuedDebtWad -= amount;
        b.committedDebtWad += amount;
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[c.positionId];
        a.committedClaimMarginWad += amount;
        --a.liveClaimCount;
    }
}

contract FifoTest is Test {
    QueueHarness internal queue;
    StaticsAccountMock internal statics;

    function setUp() public {
        statics = new StaticsAccountMock();
        statics.mint(address(this), 1);
        statics.mint(address(this), 2);
        queue = new QueueHarness(address(statics), address(new CashTokenMock(6)));
        statics.configure(address(queue), true);
    }

    function test_MonotonicClaimsAndBoundedAccountDiscovery() public {
        uint256 first = queue.seedEntitlement(1, 100e18);
        uint256 other = queue.seedEntitlement(2, 20e18);
        uint256 last = queue.seedEntitlement(1, 30e18);
        assertLt(first, other);
        assertLt(other, last);
        (uint256 head,, uint256 debt) = queue.queueState();
        assertEq(head, first);
        assertEq(debt, 150e18);
        (uint256[] memory ids, uint256 cursor) = queue.accountClaimIds(1, 0, 1);
        assertEq(ids.length, 1);
        assertEq(ids[0], first);
        (ids, cursor) = queue.accountClaimIds(1, cursor, 64);
        assertEq(ids.length, 1);
        assertEq(ids[0], last);
        assertEq(cursor, 2);
        assertEq(queue.accountState(1).liveClaimCount, 2);
        assertEq(statics.activeLegCount(1), 1);
    }

    function test_TombstoneWorkIsBoundedAndCannotSkipLiveHead() public {
        for (uint256 i; i < 5; ++i) {
            queue.seedEntitlement(1, 1e18);
        }
        for (uint256 i = 1; i <= 3; ++i) {
            queue.tombstone(i);
        }
        assertEq(queue.advanceQueue(2), 3);
        assertEq(queue.advanceQueue(2), 4);
        assertEq(queue.advanceQueue(128), 4);
        assertEq(queue.claimState(4).remainingWad, 1e18);
        assertEq(queue.book().queuedDebtWad, 2e18);
        assertEq(queue.book().committedDebtWad, 3e18);
    }

    function test_InvalidBoundsAndDustAreRejected() public {
        vm.expectRevert(LibQueue.InvalidBound.selector);
        queue.advanceQueue(0);
        vm.expectRevert(LibQueue.InvalidBound.selector);
        queue.advanceQueue(129);
        vm.expectRevert(LibQueue.InvalidBound.selector);
        queue.accountClaimIds(1, type(uint256).max, 64);
        vm.expectRevert(LibQueue.InvalidBound.selector);
        queue.accountClaimIds(1, 0, 65);
        vm.expectRevert();
        queue.seedEntitlement(1, 1);
        assertEq(queue.book().queuedDebtWad, 0);
    }
}
