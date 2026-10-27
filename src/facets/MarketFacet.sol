// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { LibMarkets } from "../libraries/LibMarkets.sol";
import { LibProtocol } from "../libraries/LibProtocol.sol";
import { LibGuard } from "../libraries/LibGuard.sol";

contract MarketFacet {
    event MarketConfigured(bytes32 indexed marketId, bytes32 indexed streamId, LibMarkets.Risk risk);
    event TermsPublished(bytes32 indexed marketId, uint64 indexed version, LibMarkets.Terms terms);
    event GlobalOiCapChanged(uint256 capWad);

    modifier governed() {
        LibGuard.enter();
        LibProtocol.requireGovernor();
        _;
        LibGuard.exit();
    }

    function configureMarket(bytes32 id, bytes32 streamId, LibMarkets.Risk calldata risk) external governed {
        LibMarkets.Market storage m = LibMarkets.state().markets[id];
        if (id == bytes32(0) || streamId == bytes32(0)) {
            revert LibMarkets.InvalidMarket();
        }
        m.streamId = streamId;
        m.risk = risk;
        emit MarketConfigured(id, streamId, risk);
    }

    function publishTerms(bytes32 id, LibMarkets.Terms calldata terms)
        external
        governed
        returns (uint64 version)
    {
        LibMarkets.State storage s = LibMarkets.state();
        LibMarkets.Market storage m = s.markets[id];
        if (m.streamId == bytes32(0)) revert LibMarkets.InvalidMarket();
        LibMarkets.validateTerms(terms);
        version = ++m.currentTermsVersion;
        s.versions[id][version] = terms;
        emit TermsPublished(id, version, terms);
    }

    function setGlobalOiCap(uint256 capWad) external governed {
        LibMarkets.state().globalOiCapWad = capWad;
        emit GlobalOiCapChanged(capWad);
    }

    function marketState(bytes32 id) external view returns (LibMarkets.Market memory) {
        return LibMarkets.state().markets[id];
    }

    function economicTerms(bytes32 id, uint64 version) external view returns (LibMarkets.Terms memory) {
        return LibMarkets.state().versions[id][version];
    }

    function globalOpenInterest() external view returns (uint256 oiWad, uint256 capWad) {
        return (LibMarkets.state().globalOiWad, LibMarkets.state().globalOiCapWad);
    }
}
