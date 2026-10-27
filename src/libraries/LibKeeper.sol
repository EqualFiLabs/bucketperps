// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibUnits } from "./LibUnits.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibFees } from "./LibFees.sol";

library LibKeeper {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.keepers.v1");

    struct State {
        uint256 totalPayableWad;
        mapping(address keeper => uint256 creditWad) credits;
    }

    event KeeperCreditAllocated(address indexed keeper, uint256 indexed tradeId, uint256 amountWad);

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function quote(uint256 margin, uint16 rateBps, uint256 cap, uint256 fundedProtocol, uint256 quantum)
        internal
        pure
        returns (uint256 amount)
    {
        amount = LibUnits.mulDivCash(margin, rateBps, 10_000, quantum);
        cap = LibUnits.floorCash(cap, quantum);
        if (amount > cap) amount = cap;
        if (amount > fundedProtocol) amount = fundedProtocol;
    }

    function credit(
        address keeper,
        uint256 tradeId,
        uint256 margin,
        LibMarkets.FeeTerms memory f,
        uint256 fundedProtocol
    ) internal returns (uint256 amount) {
        amount = quote(
            margin, f.keeperLossBps, f.keeperMaxWad, fundedProtocol, LibBookStorage.state().cashQuantum
        );
        if (amount != 0) {
            LibFees.state().protocolPayableWad -= amount;
            state().credits[keeper] += amount;
            state().totalPayableWad += amount;
        }
        emit KeeperCreditAllocated(keeper, tradeId, amount);
    }
}
