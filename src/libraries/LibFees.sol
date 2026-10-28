// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibUnits } from "./LibUnits.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { LibBookStorage } from "./LibBookStorage.sol";
import { LibStakingStorage } from "./LibStakingStorage.sol";
import { LibBook } from "./LibBook.sol";

import { LibStaking } from "./LibStaking.sol";

library LibFees {
    bytes32 internal constant SLOT = keccak256("bucketperps.storage.fees.v1");

    struct State {
        uint256 protocolPayableWad;
        uint256 operatorPayableWad;
        uint256 stakerPayableWad;
        address operatorRouter;
    }

    struct Quote {
        uint256 totalWad;
        uint256 stakerWad;
        uint256 protocolWad;
        uint256 operatorWad;
    }

    event FeesAllocated(
        uint256 requestedWad,
        uint256 fundedWad,
        uint256 stakerWad,
        uint256 protocolWad,
        uint256 operatorWad,
        uint256 retainedStakerWad
    );

    function state() internal pure returns (State storage s) {
        bytes32 slot = SLOT;
        assembly { s.slot := slot }
    }

    function quote(uint256 basis, LibMarkets.FeeTerms memory f, bool win)
        internal
        view
        returns (Quote memory q)
    {
        uint256 quantum = LibBookStorage.state().cashQuantum;
        uint256 stakerBps = win ? f.winStakerBps : f.lossStakerBps;
        uint256 protocolBps = win ? f.winProtocolBps : f.lossProtocolBps;
        uint256 operatorBps = win ? f.winOperatorBps : f.lossOperatorBps;
        q.totalWad = LibUnits.fee(basis, stakerBps + protocolBps + operatorBps, quantum);
        q.stakerWad = LibUnits.fee(basis, stakerBps, quantum);
        q.operatorWad = LibUnits.fee(basis, operatorBps, quantum);
        q.protocolWad = q.totalWad - q.stakerWad - q.operatorWad;
    }

    /// @dev Eligibility requires the entire quoted fee, even if the zero-weight slice will be retained.
    function fund(Quote memory q) internal returns (uint256 funded, uint256 protocolFunded) {
        if (q.totalWad == 0) return (0, 0);
        if (LibBookStorage.state().queuedDebtWad != 0 || LibBook.directBudget() < q.totalWad) {
            emit FeesAllocated(q.totalWad, 0, 0, 0, 0, 0);
            return (0, 0);
        }
        uint256 retained;
        if (LibStakingStorage.state().totalEffectiveWeight == 0) {
            retained = q.stakerWad;
            q.stakerWad = 0;
        }
        funded = q.totalWad - retained;
        protocolFunded = q.protocolWad;
        State storage s = state();
        s.protocolPayableWad += q.protocolWad;
        s.operatorPayableWad += q.operatorWad;
        s.stakerPayableWad += q.stakerWad;
        LibStaking.distribute(q.stakerWad);
        LibBookStorage.state().fundedPayablesWad += funded;
        emit FeesAllocated(q.totalWad, funded, q.stakerWad, q.protocolWad, q.operatorWad, retained);
    }
}
