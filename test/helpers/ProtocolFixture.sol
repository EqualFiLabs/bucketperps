// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BucketPerpsDiamond } from "../../src/BucketPerpsDiamond.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IStaticsExecutionOracle } from "../../src/interfaces/IStaticsExecutionOracle.sol";
import { AccountsInit } from "../../src/init/AccountsInit.sol";
import { CashInit } from "../../src/init/CashInit.sol";
import { OracleInit } from "../../src/init/OracleInit.sol";
import { AccountFacet } from "../../src/facets/AccountFacet.sol";
import { CashFacet } from "../../src/facets/CashFacet.sol";
import { MarketFacet } from "../../src/facets/MarketFacet.sol";
import { TradingFacet } from "../../src/facets/TradingFacet.sol";
import { QueueFacet } from "../../src/facets/QueueFacet.sol";
import { SettlementFacet } from "../../src/facets/SettlementFacet.sol";
import { FeeFacet } from "../../src/facets/FeeFacet.sol";
import { HouseFacet } from "../../src/facets/HouseFacet.sol";
import { LiquidationFacet } from "../../src/facets/LiquidationFacet.sol";
import { LibBookStorage } from "../../src/libraries/LibBookStorage.sol";
import { LibFees } from "../../src/libraries/LibFees.sol";
import { LibGuard } from "../../src/libraries/LibGuard.sol";
import { LibQueue } from "../../src/libraries/LibQueue.sol";
import { LibPnl } from "../../src/libraries/LibPnl.sol";
import { LibMarkets } from "../../src/libraries/LibMarkets.sol";
import { CashTokenMock } from "../mocks/CashTokenMock.sol";
import { StaticsAccountMock } from "../mocks/StaticsAccountMock.sol";
import { ExecutionOracleMock } from "../mocks/ExecutionOracleMock.sol";
import { OpenParams, ClaimPortion, FundingSource } from "../../src/types/TradingTypes.sol";

/// @dev Fixture orchestration of the production component initializers, not a deployment script.
contract FixtureInit {
    address private immutable accounts = address(new AccountsInit());
    address private immutable cash = address(new CashInit());
    address private immutable oracle = address(new OracleInit());

    function initialize(address nft, address token, address adapter) external {
        _run(accounts, abi.encodeCall(AccountsInit.initialize, (nft, nft)));
        _run(cash, abi.encodeCall(CashInit.initialize, (token)));
        _run(oracle, abi.encodeCall(OracleInit.initialize, (adapter)));
    }

    function _run(address target, bytes memory data) private {
        (bool ok, bytes memory result) = target.delegatecall(data);
        if (!ok) {
            assembly { revert(add(result, 32), mload(result)) }
        }
    }
}

/// @dev Test-only state seeding and inspection. Never part of a production selector manifest.
contract FixtureBookFacet {
    function book() external view returns (LibBookStorage.State memory) {
        return LibBookStorage.state();
    }

    function fees() external view returns (LibFees.State memory) {
        return LibFees.state();
    }

    function seedEntitlement(uint256 id, uint256 wad) external returns (uint256 claimId) {
        LibGuard.enter();
        LibBookStorage.state().realizedHousePnlWad -= int256(wad);
        claimId = LibQueue.enqueue(id, wad);
        LibGuard.exit();
    }

    function seedPriorCashOutcome(uint256 wad) external {
        LibBookStorage.state().custodyWad += wad;
        LibBookStorage.state().realizedHousePnlWad += int256(wad);
    }
}

abstract contract ProtocolFixture is Test {
    bytes32 internal constant MARKET = keccak256("fixture market");
    bytes32 internal constant STREAM = keccak256("fixture stream");
    BucketPerpsDiamond internal diamond;
    CashTokenMock internal token;
    StaticsAccountMock internal statics;
    ExecutionOracleMock internal oracle;
    CashFacet internal cash;
    AccountFacet internal accounts;
    MarketFacet internal markets;
    TradingFacet internal trading;
    QueueFacet internal queue;
    SettlementFacet internal settlement;
    FeeFacet internal feeFacet;
    HouseFacet internal houseFacet;
    LiquidationFacet internal liquidation;
    FixtureBookFacet internal bookView;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new CashTokenMock(6);
        statics = new StaticsAccountMock();
        oracle = new ExecutionOracleMock();
        statics.mint(alice, 1);
        statics.mint(bob, 2);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](10);
        bytes4[] memory s = new bytes4[](3);
        s[0] = AccountFacet.accountState.selector;
        s[1] = AccountFacet.hasUnresolvedAccountState.selector;
        s[2] = AccountFacet.syncAccountActivity.selector;
        cuts[0] = _cut(address(new AccountFacet()), s);
        s = new bytes4[](2);
        s[0] = CashFacet.deposit.selector;
        s[1] = CashFacet.withdraw.selector;
        cuts[1] = _cut(address(new CashFacet()), s);
        s = new bytes4[](6);
        s[0] = MarketFacet.configureMarket.selector;
        s[1] = MarketFacet.publishTerms.selector;
        s[2] = MarketFacet.setGlobalOiCap.selector;
        s[3] = MarketFacet.marketState.selector;
        s[4] = MarketFacet.economicTerms.selector;
        s[5] = MarketFacet.globalOpenInterest.selector;
        cuts[2] = _cut(address(new MarketFacet()), s);
        s = new bytes4[](2);
        s[0] = TradingFacet.openPosition.selector;
        s[1] = TradingFacet.tradeState.selector;
        cuts[3] = _cut(address(new TradingFacet()), s);
        s = new bytes4[](6);
        s[0] = QueueFacet.queueState.selector;
        s[1] = QueueFacet.claimState.selector;
        s[2] = QueueFacet.accountClaimIds.selector;
        s[3] = QueueFacet.queueBounds.selector;
        s[4] = QueueFacet.advanceQueue.selector;
        s[5] = QueueFacet.harvest.selector;
        cuts[4] = _cut(address(new QueueFacet()), s);
        s = new bytes4[](1);
        s[0] = SettlementFacet.closePosition.selector;
        cuts[5] = _cut(address(new SettlementFacet()), s);
        s = new bytes4[](4);
        s[0] = FixtureBookFacet.book.selector;
        s[1] = FixtureBookFacet.fees.selector;
        s[2] = FixtureBookFacet.seedEntitlement.selector;
        s[3] = FixtureBookFacet.seedPriorCashOutcome.selector;
        cuts[6] = _cut(address(new FixtureBookFacet()), s);
        s = new bytes4[](2);
        s[0] = FeeFacet.feePayables.selector;
        s[1] = FeeFacet.withdrawProtocolFees.selector;
        cuts[7] = _cut(address(new FeeFacet()), s);
        s = new bytes4[](5);
        s[0] = HouseFacet.unassignedSettlementUnits.selector;
        s[1] = HouseFacet.classifySettlementDonation.selector;
        s[2] = HouseFacet.surplusConfiguration.selector;
        s[3] = HouseFacet.distributeSurplus.selector;
        s[4] = HouseFacet.configureSurplus.selector;
        cuts[8] = _cut(address(new HouseFacet()), s);
        s = new bytes4[](1);
        s[0] = LiquidationFacet.liquidate.selector;
        cuts[9] = _cut(address(new LiquidationFacet()), s);
        diamond = new BucketPerpsDiamond(
            BucketPerpsDiamond.Bootstrap({
                governor: address(this),
                guardian: bob,
                upgradeDelay: 1 days,
                cuts: cuts,
                init: address(new FixtureInit()),
                data: abi.encodeCall(
                    FixtureInit.initialize, (address(statics), address(token), address(oracle))
                )
            })
        );
        cash = CashFacet(address(diamond));
        accounts = AccountFacet(address(diamond));
        markets = MarketFacet(address(diamond));
        trading = TradingFacet(address(diamond));
        queue = QueueFacet(address(diamond));
        settlement = SettlementFacet(address(diamond));
        feeFacet = FeeFacet(address(diamond));
        houseFacet = HouseFacet(address(diamond));
        liquidation = LiquidationFacet(address(diamond));
        bookView = FixtureBookFacet(address(diamond));
        statics.configure(address(diamond), true);
        markets.configureMarket(MARKET, STREAM, _risk());
        markets.publishTerms(MARKET, _terms());
        markets.setGlobalOiCap(10_000_000e18);
        _price(50_000e18);
        _deposit(alice, 1, 1_000e6);
        _deposit(bob, 2, 1_000e6);
    }

    function _cut(address facet, bytes4[] memory selectors)
        internal
        pure
        returns (IDiamondCut.FacetCut memory)
    {
        return IDiamondCut.FacetCut(facet, IDiamondCut.FacetCutAction.Add, selectors);
    }

    function _deposit(address owner, uint256 id, uint256 units) internal {
        token.mint(owner, units);
        vm.startPrank(owner);
        token.approve(address(diamond), type(uint256).max);
        cash.deposit(id, units);
        vm.stopPrank();
    }

    function _price(uint256 price) internal {
        oracle.setResponse(IStaticsExecutionOracle.ExecutionPrice(price, 100, 99, 101, STREAM));
    }

    function _house(uint256 amount) internal {
        token.mint(address(diamond), amount / 1e12);
        bookView.seedPriorCashOutcome(amount);
    }

    function _params(bool isLong, FundingSource source) internal view returns (OpenParams memory) {
        return OpenParams(MARKET, isLong, source, 100e18, 100, 1, block.timestamp);
    }

    function _openCash(uint256 id, address owner, bool isLong) internal returns (uint256 tradeId) {
        vm.prank(owner);
        return trading.openPosition(
            id, _params(isLong, FundingSource.Cash), new ClaimPortion[](0), new bytes[](0)
        );
    }

    function _openClaim(uint256 id, address owner, uint256 claimId) internal returns (uint256 tradeId) {
        ClaimPortion[] memory portions = new ClaimPortion[](1);
        portions[0] = ClaimPortion(claimId, 100e18);
        vm.prank(owner);
        return trading.openPosition(id, _params(true, FundingSource.Claim), portions, new bytes[](0));
    }

    function _risk() internal pure returns (LibMarkets.Risk memory) {
        return LibMarkets.Risk(
            true, true, 100, 1e18, 100_000e18, 1e18, 1_000_000e18, 5_000_000e18, 5_000_000e18, 10_000_000e18
        );
    }

    function _terms() internal pure returns (LibMarkets.Terms memory) {
        return LibMarkets.Terms(
            LibMarkets.FeeTerms(100, 70, 20, 100, 80, 20, 40, 1e18),
            LibPnl.Curve(0.02e18, 2e18, 1e18, 5e23, false),
            5e14
        );
    }
}
