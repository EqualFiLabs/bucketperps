// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibBook } from "../libraries/LibBook.sol";
import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { LibTrades } from "../libraries/LibTrades.sol";
import { LibStaking } from "../libraries/LibStaking.sol";
import { LibRewards } from "../libraries/LibRewards.sol";
import { LibMarkets } from "../libraries/LibMarkets.sol";
import { LibFees } from "../libraries/LibFees.sol";
import { LibKeeper } from "../libraries/LibKeeper.sol";

contract ViewFacet {
    error InvalidPage();

    struct LedgerView {
        LibBookStorage.State book;
        uint256 houseCashWad;
        uint256 directBudgetWad;
        uint256 actualSettlementUnits;
        LibFees.State fees;
        uint256 keeperPayableWad;
    }

    function ledgerState() external view returns (LedgerView memory v) {
        v.book = LibBookStorage.state();
        v.houseCashWad = LibBook.houseCash();
        v.directBudgetWad = LibBook.directBudget();
        v.actualSettlementUnits = IERC20(v.book.settlementToken).balanceOf(address(this));
        v.fees = LibFees.state();
        v.keeperPayableWad = LibKeeper.state().totalPayableWad;
    }

    function accountOverview(uint256 id)
        external
        view
        returns (address owner, LibAccountsStorage.Account memory account, uint256 pendingRevenueWad)
    {
        owner = LibAccounts.owner(id);
        account = LibAccountsStorage.state().accounts[id];
        (uint256 earned,) = LibStaking.accrued(id);
        pendingRevenueWad = account.claimableRevenueWad + earned;
    }

    function externalAccountIdentity(uint256 id)
        external
        view
        returns (bytes32 moduleType, bytes32 localAccountId, bool active)
    {
        moduleType = LibAccounts.MODULE_TYPE;
        localAccountId = bytes32(id);
        active = LibAccountsStorage.state().accounts[id].externalStateActive;
    }

    function accountTradeIds(uint256 id, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory ids, uint256 nextCursor)
    {
        uint256[] storage all = LibTrades.state().accountTradeIds[id];
        if (limit == 0 || limit > 64 || cursor > all.length) revert InvalidPage();
        uint256 count = all.length - cursor;
        if (count > limit) count = limit;
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = all[cursor + i];
        }
        return (ids, cursor + count);
    }

    function tradeContext(uint256 id)
        external
        view
        returns (
            LibTrades.Trade memory trade,
            LibMarkets.Terms memory openingTerms,
            bytes32 currentStream,
            uint256 currentRewardRate
        )
    {
        trade = LibTrades.state().trades[id];
        openingTerms = LibMarkets.state().versions[trade.marketId][trade.termsVersion];
        currentStream = LibMarkets.state().markets[trade.marketId].streamId;
        currentRewardRate = LibRewards.state().rewardUnitsPerDollar;
    }

    function rewardBacking()
        external
        view
        returns (
            uint256 inventoryUnits,
            uint256 allocatedUnits,
            uint256 receiptSupply,
            uint256 actualInventoryUnits,
            uint256 actualBackingUnits
        )
    {
        LibRewards.State storage s = LibRewards.state();
        inventoryUnits = s.inventoryUnits;
        allocatedUnits = s.allocatedUnits;
        if (s.receipt != address(0)) receiptSupply = IERC20(s.receipt).totalSupply();
        if (s.staticsToken != address(0)) {
            actualInventoryUnits = IERC20(s.staticsToken).balanceOf(address(this));
            actualBackingUnits = IERC20(s.staticsToken).balanceOf(s.backingVault);
        }
    }
}
