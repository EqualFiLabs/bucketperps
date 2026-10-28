// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { LibStaking } from "../../src/libraries/LibStaking.sol";
import { LibStakingStorage } from "../../src/libraries/LibStakingStorage.sol";
import { LibAccountsStorage } from "../../src/libraries/LibAccountsStorage.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibFees } from "../../src/libraries/LibFees.sol";

contract StakingIndexHarness {
    constructor() {
        LibBookStorage.state().cashQuantum = 1;
        LibBookStorage.state().custodyWad = 1000e18;
    }

    function weight(uint256 id, uint256 weight_) external {
        LibStaking.checkpoint(id);
        LibAccountsStorage.Account storage a = LibAccountsStorage.state().accounts[id];
        LibStakingStorage.state().totalEffectiveWeight =
            LibStakingStorage.state().totalEffectiveWeight - a.effectiveWeight + weight_;
        a.effectiveWeight = weight_;
    }

    function fund(uint256 amount) external {
        LibFees.fund(LibFees.Quote(amount, amount, 0, 0));
    }

    function earned(uint256 id) external returns (uint256) {
        LibStaking.checkpoint(id);
        return LibAccountsStorage.state().accounts[id].claimableRevenueWad;
    }

    function liability() external view returns (uint256) {
        return LibBookStorage.state().fundedPayablesWad;
    }
}

contract StakingIndexTest is Test {
    function testProspectiveWeightAndZeroWeightRetention() public {
        StakingIndexHarness h = new StakingIndexHarness();
        h.fund(100e18);
        assertEq(h.liability(), 0);
        h.weight(1, 10e18);
        h.fund(100e18);
        h.weight(2, 10e18);
        h.fund(100e18);
        assertEq(h.earned(1), 150e18);
        assertEq(h.earned(2), 50e18);
        assertEq(h.liability(), 200e18);
    }

    function testFuzzFrequentCheckpointCannotInflateRevenue(uint96 rawWeight, uint96 revenue) public {
        uint256 w = bound(rawWeight, 1, 1e24);
        uint256 fee = bound(revenue, 1, 100e18);
        StakingIndexHarness h = new StakingIndexHarness();
        h.weight(1, w);
        for (uint256 i; i < 5; ++i) {
            h.fund(fee);
            h.earned(1);
        }
        uint256 earned = h.earned(1);
        assertLe(earned, 5 * fee);
        assertLe(5 * fee - earned, 5 * w / 1e27 + 1);
        assertEq(h.liability(), 5 * fee);
    }
}
