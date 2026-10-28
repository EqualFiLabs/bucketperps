# BucketPerps

BucketPerps is a synthetic perpetual trading house whose complete accounts belong
to Statics PositionNFTs. Cash margin and queued-claim margin remain separate;
unpaid realized entitlements enter a strict FIFO queue. Price authentication is
provided by the external Statics execution oracle.

Qualifying losses issue BPERP, a restricted receipt backed one-for-one by existing
STATICS. Account-held BPERP can be staked for funded trading-fee revenue. Receipt
holdings, staking revenue, trades, cash and claims follow current NFT ownership.
ERC-721 approvals do not grant financial authority.

Public wrapping and unwrapping start disabled, with zero wrapping capacity.
Future conversion controls are distinct from underlying STATICS minting/burning.
Loss rewards are capped by available backing inventory and create no reward IOU.
When no effective stake exists, the staker fee slice remains house cash.

The implementation uses a standalone Diamond with namespaced storage. USDG is the
launch settlement asset; a fixed future USDstx conversion is separately gated.
Execution-oracle, Statics account hooks, fee routing and Dollar compatibility must
be qualified against their actual implementations before affected production use.

This repository is under development. Test settings are fixtures, and no release
configuration or production compatibility is implied.

## Development

Use Foundry v1.8.6 and initialize the pinned submodules recursively. Solidity
0.8.33 targets the Paris EVM with 200 optimizer runs. OpenZeppelin Contracts
v5.7.0 and forge-std v1.17.0 are pinned by submodule commit.

```sh
git submodule update --init --recursive
forge fmt --check
forge build --sizes
forge test
FOUNDRY_PROFILE=ci forge test
```

CI runs the extended fuzz and invariant profile. Production configuration must
provide separately qualified dependencies and explicitly selected launch values.

Client workflows are documented in [Direct account integration](docs/client-integration.md)
and the [event reference](docs/events.md).
