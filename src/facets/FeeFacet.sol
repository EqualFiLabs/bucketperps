// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibFees } from "../libraries/LibFees.sol";
import { LibBookStorage } from "../libraries/LibBookStorage.sol";
import { LibCash } from "../libraries/LibCash.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibUnits } from "../libraries/LibUnits.sol";
import { IOperatorFeeRouter } from "../interfaces/IOperatorFeeRouter.sol";

contract FeeFacet {
    using SafeERC20 for IERC20;
    event OperatorFeesDelivered(address indexed router, uint256 amountWad);

    /// @notice Independent delivery; a router failure cannot interrupt trade settlement.
    function flushOperatorFees(uint256 amountWad) external {
        LibGuard.enter();
        LibCash.requireBacking();
        if (amountWad == 0) revert LibCash.InvalidAmount();
        LibFees.State storage f = LibFees.state();
        LibBookStorage.State storage b = LibBookStorage.state();
        address router = f.operatorRouter;
        uint256 units = LibUnits.toTokenUnits(amountWad, b.cashQuantum);
        IERC20 token = IERC20(b.settlementToken);
        uint256 beforeHere = token.balanceOf(address(this));
        uint256 beforeThere = token.balanceOf(router);
        f.operatorPayableWad -= amountWad;
        b.fundedPayablesWad -= amountWad;
        b.custodyWad -= amountWad;
        token.forceApprove(router, units);
        IOperatorFeeRouter(router).addRewards(b.settlementToken, units);
        token.forceApprove(router, 0);
        if (
            token.balanceOf(address(this)) + units != beforeHere
                || token.balanceOf(router) != beforeThere + units
        ) revert LibCash.InexactTransfer();
        emit OperatorFeesDelivered(router, amountWad);
        LibGuard.exit();
    }

    event ProtocolFeesWithdrawn(address indexed receiver, uint256 amountWad);

    function feePayables() external view returns (LibFees.State memory) {
        return LibFees.state();
    }

    function withdrawProtocolFees(uint256 amountWad, address receiver) external {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        LibFees.state().protocolPayableWad -= amountWad;
        LibBookStorage.state().fundedPayablesWad -= amountWad;
        LibCash.sendExact(receiver, amountWad);
        emit ProtocolFeesWithdrawn(receiver, amountWad);
        LibGuard.exit();
    }
}
