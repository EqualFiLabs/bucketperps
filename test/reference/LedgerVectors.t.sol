// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

/// @notice Independent acceptance vectors for later production settlement and queue tests.
/// @dev No production settlement routine is used to derive these expected states.
contract LedgerVectorsTest is Test {
    struct Book {
        uint256 c;
        uint256 d;
        uint256 f;
        uint256 h;
        uint256 m;
        int256 p;
        uint256 q;
        uint256 s;
        uint256 t;
    }

    struct Vector {
        Book afterBook;
        uint256 amount;
        uint256 basis;
        Book beforeBook;
        uint256 fundedFee;
        string id;
        string kind;
        uint256 nominalFee;
        uint256 retainedStaker;
    }

    function vectors() internal view returns (Vector[] memory) {
        return
            abi.decode(vm.parseJson(vm.readFile("test/fixtures/ledger-vectors.json"), ".vectors"), (Vector[]));
    }

    function net(Book memory b) internal pure returns (int256) {
        return int256(b.h) - int256(b.q) - int256(b.d);
    }

    function checkBook(Book memory b) internal pure {
        assertEq(b.t, b.c + b.m + b.f + b.h);
        assertLe(b.s, b.h);
        if (b.q == 0) assertEq(b.s, 0, "no stranded side bucket");
    }

    function test_AllVectorsConserveCustodyAndEconomicEquity() public view {
        Vector[] memory rows = vectors();
        assertEq(rows.length, 20);
        for (uint256 i; i < rows.length; ++i) {
            Vector memory r = rows[i];
            checkBook(r.beforeBook);
            checkBook(r.afterBook);
            // Every represented operation affects cash/debt equity exactly as tracked PnL.
            // External funding/donation classification is deliberately outside this corpus.
            assertEq(net(r.afterBook) - net(r.beforeBook), r.afterBook.p - r.beforeBook.p, r.id);
            bytes32 kind = keccak256(bytes(r.kind));
            int256 expectedFeeDelta = kind == keccak256("feeCredit") || kind == keccak256("feeDelivery")
                ? -int256(r.amount)
                : int256(r.fundedFee);
            assertEq(int256(r.afterBook.f) - int256(r.beforeBook.f), expectedFeeDelta, r.id);
            assertTrue(
                r.fundedFee + r.retainedStaker == 0 || r.fundedFee + r.retainedStaker == r.nominalFee, r.id
            );
        }
    }

    function test_TradeRecognitionIncludesOnlyActuallyFundedFees() public view {
        Vector[] memory rows = vectors();
        uint256 wins;
        uint256 losses;
        for (uint256 i; i < rows.length; ++i) {
            Vector memory r = rows[i];
            bytes32 kind = keccak256(bytes(r.kind));
            if (kind == keccak256("cashWin") || kind == keccak256("claimWin")) {
                uint256 netProfit = r.basis - r.nominalFee;
                assertEq(r.afterBook.p - r.beforeBook.p, -int256(netProfit + r.fundedFee), r.id);
                ++wins;
            } else if (
                kind == keccak256("cashLoss") || kind == keccak256("claimLoss")
                    || kind == keccak256("claimBust")
            ) {
                assertEq(r.afterBook.p - r.beforeBook.p, int256(r.basis - r.fundedFee), r.id);
                if (kind == keccak256("claimLoss") || kind == keccak256("claimBust")) {
                    assertLe(r.afterBook.h, r.beforeBook.h, "debt cancellation creates no cash");
                    assertEq(r.afterBook.t, r.beforeBook.t);
                }
                ++losses;
            }
        }
        assertEq(wins, 4);
        assertEq(losses, 8);
    }

    function test_DebtReuseHarvestAndFeePayoutCannotRecognizePnlAgain() public view {
        Vector[] memory rows = vectors();
        uint256 checked;
        for (uint256 i; i < rows.length; ++i) {
            Vector memory r = rows[i];
            bytes32 kind = keccak256(bytes(r.kind));
            if (kind == keccak256("claimOpen")) {
                assertEq(r.beforeBook.q - r.afterBook.q, r.amount);
                assertEq(r.afterBook.d - r.beforeBook.d, r.amount);
                assertEq(r.afterBook.h, r.beforeBook.h);
            } else if (kind == keccak256("harvest")) {
                assertEq(r.beforeBook.h - r.afterBook.h, r.amount);
                assertEq(r.afterBook.c - r.beforeBook.c, r.amount);
                assertEq(r.beforeBook.q - r.afterBook.q, r.amount);
                assertEq(
                    r.afterBook.s,
                    r.afterBook.q == 0 || r.amount >= r.beforeBook.s ? 0 : r.beforeBook.s - r.amount
                );
            } else if (kind == keccak256("feeCredit")) {
                assertEq(r.beforeBook.f - r.afterBook.f, r.amount);
                assertEq(r.afterBook.c - r.beforeBook.c, r.amount);
                assertEq(r.afterBook.h, r.beforeBook.h);
            } else if (kind == keccak256("feeDelivery")) {
                assertEq(r.beforeBook.f - r.afterBook.f, r.amount);
                assertEq(r.beforeBook.t - r.afterBook.t, r.amount);
                assertEq(r.afterBook.h, r.beforeBook.h);
            } else {
                continue;
            }
            assertEq(r.afterBook.p, r.beforeBook.p, r.id);
            ++checked;
        }
        assertEq(checked, 6);
    }
}
