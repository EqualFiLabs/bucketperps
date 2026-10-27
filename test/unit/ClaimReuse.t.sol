// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ClaimFundingFixture } from "./ClaimFunding.t.sol";
import { ClaimPortion, OpenParams } from "../../src/types/TradingTypes.sol";
import { LibAccounts } from "../../src/libraries/LibAccounts.sol";
import { LibQueue } from "../../src/libraries/LibQueue.sol";

contract ClaimReuseTest is ClaimFundingFixture {
    function testFuzz_PartialReuseConservesDebtWithoutCashCreation(uint64 totalSeed, uint64 usedSeed) public {
        uint256 totalUnits = bound(totalSeed, 1e6, 1_000e6);
        uint256 used = bound(usedSeed, 1e6, totalUnits) * 1e12;
        uint256 id = claims.seedEntitlement(1, totalUnits * 1e12);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(id, used);
        OpenParams memory p = _claimParams();
        p.marginWad = used;
        p.leverage = 2;
        int256 beforeP = trading.book().realizedHousePnlWad;
        vm.prank(alice);
        trading.openPosition(1, p, portions, new bytes[](0));
        assertEq(trading.book().queuedDebtWad + trading.book().committedDebtWad, totalUnits * 1e12);
        assertEq(trading.book().committedDebtWad, used);
        assertEq(trading.book().custodyWad, 1_000e18);
        assertEq(trading.book().accountCashWad, 1_000e18);
        assertEq(trading.book().lockedCashMarginWad, 0);
        assertEq(trading.book().fundedPayablesWad, 0);
        assertEq(trading.book().realizedHousePnlWad, beforeP);
    }

    function test_TombstonesConsumeWorkBudgetBeforeLaterPayouts() public {
        for (uint256 i; i < 5; ++i) {
            claims.seedEntitlement(1, 1e18);
        }
        ClaimPortion[] memory portions = new ClaimPortion[](3);
        for (uint256 i; i < 3; ++i) {
            portions[i] = ClaimPortion(i + 1, 1e18);
        }
        OpenParams memory p = _claimParams();
        p.marginWad = 3e18;
        p.leverage = 2;
        vm.prank(alice);
        trading.openPosition(1, p, portions, new bytes[](0));
        token.mint(address(trading), 10e6);
        claims.seedHouse(10e18, 10e18);
        int256 beforeP = trading.book().realizedHousePnlWad;
        assertEq(claims.harvest(2), 0);
        (uint256 head,,) = claims.queueState();
        assertEq(head, 3);
        assertEq(claims.harvest(1), 0);
        assertEq(claims.harvest(1), 1e18);
        assertEq(claims.claimState(5).remainingWad, 1e18);
        assertEq(claims.harvest(1), 1e18);
        assertEq(trading.book().sideBucketWad, 0);
        assertEq(trading.book().committedDebtWad, 3e18);
        assertEq(trading.book().realizedHousePnlWad, beforeP);
    }

    function test_ConsumingLastClaimReleasesEarmarkAndNewEntitlementHasNewPriority() public {
        uint256 old = claims.seedEntitlement(1, 100e18);
        token.mint(address(trading), 150e6);
        claims.seedHouse(150e18, 150e18);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(old, 100e18);
        vm.prank(alice);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(trading.book().sideBucketWad, 0);
        uint256 fresh = claims.seedEntitlement(1, 20e18);
        assertGt(fresh, old);
        (uint256 head,,) = claims.queueState();
        assertEq(head, fresh);
        assertEq(claims.harvest(1), 20e18);
        assertEq(trading.book().committedDebtWad, 100e18);
        assertEq(trading.book().queuedDebtWad, 0);
    }

    function test_NftSaleTransfersOnlyRemainingClaimAuthority() public {
        uint256 id = claims.seedEntitlement(1, 200e18);
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(id, 100e18);
        vm.prank(alice);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        vm.prank(alice);
        statics.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert(LibAccounts.NotPositionOwner.selector);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        vm.prank(bob);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(claims.claimState(id).remainingWad, 0);
        assertEq(trading.book().committedDebtWad, 200e18);
        assertEq(trading.accountState(1).openTradeCount, 2);
        vm.prank(bob);
        vm.expectRevert();
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(trading.book().committedDebtWad, 200e18);
    }

    function test_PortionsBeyondBoundFailBeforeAnyClaimMutation() public {
        uint256 id = claims.seedEntitlement(1, 100e18);
        ClaimPortion[] memory portions = new ClaimPortion[](33);
        vm.prank(alice);
        vm.expectRevert(LibQueue.InvalidBound.selector);
        trading.openPosition(1, _claimParams(), portions, new bytes[](0));
        assertEq(claims.claimState(id).remainingWad, 100e18);
        assertEq(trading.book().committedDebtWad, 0);
    }
}
