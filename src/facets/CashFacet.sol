// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibAccounts } from "../libraries/LibAccounts.sol";
import { LibAccountsStorage } from "../libraries/LibAccountsStorage.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibCash } from "../libraries/LibCash.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract CashFacet {
    event Deposited(uint256 indexed positionId, address indexed owner, uint256 tokenUnits, uint256 amountWad);
    event Withdrawn(uint256 indexed positionId, address indexed receiver, uint256 amountWad);

    function deposit(uint256 positionId, uint256 tokenUnits) external {
        LibGuard.enter();
        LibAccounts.requireOwner(positionId);
        uint256 wad = LibCash.receiveExact(msg.sender, tokenUnits);
        LibAccountsStorage.state().accounts[positionId].cashWad += wad;
        LibBookStorage.state().accountCashWad += wad;
        LibAccounts.syncActivity(positionId);
        emit Deposited(positionId, msg.sender, tokenUnits, wad);
        LibGuard.exit();
    }

    function withdraw(uint256 positionId, uint256 amountWad, address receiver) external {
        LibGuard.enter();
        LibAccounts.requireOwner(positionId);
        LibAccountsStorage.state().accounts[positionId].cashWad -= amountWad;
        LibBookStorage.state().accountCashWad -= amountWad;
        LibCash.sendExact(receiver, amountWad);
        LibAccounts.syncActivity(positionId);
        emit Withdrawn(positionId, receiver, amountWad);
        LibGuard.exit();
    }
}
