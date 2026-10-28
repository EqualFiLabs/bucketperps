// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { ControlProtocolFixture } from "../helpers/ControlProtocolFixture.sol";

/// @dev Local EVM fixtures. These measurements do not select production risk or keeper settings.
contract ExecutionMeasurementsTest is ControlProtocolFixture {
    event ActionGas(bytes32 indexed action, uint256 gasUsed);

    function testMeasureCashCloseAndZeroBountyClaimBust() public {
        uint256 start = gasleft();
        uint256 cashTrade = _openCash(1, alice, true);
        emit ActionGas("cash-open", start - gasleft());
        _price(49_900e18);
        start = gasleft();
        vm.prank(alice);
        settlement.closePosition(1, cashTrade, block.timestamp, new bytes[](0));
        emit ActionGas("cash-loss-close", start - gasleft());
        uint256 claim = bookView.seedEntitlement(2, 100e18);
        _price(50_000e18);
        start = gasleft();
        uint256 claimTrade = _openClaim(2, bob, claim);
        emit ActionGas("claim-open", start - gasleft());
        _price(1e18);
        start = gasleft();
        liquidation.liquidate(2, claimTrade, new bytes[](0));
        emit ActionGas("claim-bust-zero-bounty", start - gasleft());
        assertEq(liquidation.keeperPayable(address(this)), 0);
        assertEq(trading.tradeState(claimTrade).settled, true);
    }

    function testMeasureFifoHarvestAndRevenueClaim() public {
        _earnReceipts(1, alice);
        vm.prank(alice);
        staking.stake(1, 10e18);
        _earnReceipts(2, bob);
        uint256 start = gasleft();
        vm.prank(alice);
        staking.claimStakerRevenue(1);
        emit ActionGas("revenue-claim", start - gasleft());
        bookView.seedEntitlement(2, 10e18);
        start = gasleft();
        queue.harvest(128);
        emit ActionGas("fifo-harvest", start - gasleft());
        (,, uint256 debt) = queue.queueState();
        assertEq(debt, 0);
    }
}
