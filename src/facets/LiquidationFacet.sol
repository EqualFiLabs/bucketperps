// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibSettlement } from "../libraries/LibSettlement.sol";
import { LibGuard } from "../libraries/LibGuard.sol";
import { LibKeeper } from "../libraries/LibKeeper.sol";
import { LibTrades } from "../libraries/LibTrades.sol";
import { LibMarkets } from "../libraries/LibMarkets.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibCash } from "../libraries/LibCash.sol";
import { FundingSource } from "../types/TradingTypes.sol";

import { LibControls } from "../libraries/LibControls.sol";

contract LiquidationFacet {
    event LiquidationExecuted(
        uint256 indexed tradeId,
        uint256 indexed positionId,
        address indexed keeper,
        uint256 forfeitedMarginWad,
        uint256 keeperCreditWad
    );
    event KeeperCreditWithdrawn(address indexed keeper, address indexed receiver, uint256 amountWad);

    function liquidate(uint256 positionId, uint256 tradeId, bytes[] calldata fullReports)
        external
        returns (LibSettlement.Result memory result)
    {
        LibGuard.enter();
        result = LibSettlement.settle(positionId, tradeId, fullReports, true);
        LibTrades.Trade storage t = LibTrades.state().trades[tradeId];
        uint256 credit;
        if (t.fundingSource == FundingSource.Cash) {
            credit = LibKeeper.credit(
                msg.sender,
                tradeId,
                result.lossWad,
                LibMarkets.state().versions[t.marketId][t.termsVersion].fees,
                result.fundedProtocolWad
            );
        }
        emit LiquidationExecuted(tradeId, positionId, msg.sender, result.lossWad, credit);
        LibGuard.exit();
    }

    function keeperPayable(address keeper) external view returns (uint256) {
        return LibKeeper.state().credits[keeper];
    }

    function totalKeeperPayable() external view returns (uint256) {
        return LibKeeper.state().totalPayableWad;
    }

    function withdrawKeeperCredit(uint256 amountWad, address receiver) external {
        LibGuard.enter();
        LibControls.requireClear(LibControls.FEES);
        LibKeeper.State storage s = LibKeeper.state();
        s.credits[msg.sender] -= amountWad;
        s.totalPayableWad -= amountWad;
        LibBookStorage.state().fundedPayablesWad -= amountWad;
        LibCash.sendExact(receiver, amountWad);
        emit KeeperCreditWithdrawn(msg.sender, receiver, amountWad);
        LibGuard.exit();
    }
}
