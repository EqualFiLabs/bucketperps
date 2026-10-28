# Direct account integration

All financial calls use the current Position NFT owner at execution time. ERC-721
approvals permit NFT transfer where Statics permits it; they do not grant trading,
staking or withdrawal authority. A submitted transaction can fail if ownership
changes before inclusion. Supply a deadline and the intended economic version
when opening. Economic versions are append-only; admission limits apply only to
new positions. Stream rotation applies to later price verification, including
settlement of existing positions, without changing their entry or bust terms.

## Independent execution and reports

A frontend can call the Diamond directly; no relayer signature or endpoint proof
is required. Pass the full signed report bundle unchanged. Obtain reports through
your own licensed access or another lawful delivery path accepted by the configured
oracle. BucketPerps does not give callers access to a service's Chainlink credentials
or subscription. Verification, matching, report windows, sequencer checks, consumer
authorization and billing belong to the external execution oracle.

Read the current market stream and oracle configuration before constructing the
bundle. Do not substitute a price feed because its payload is signed: it must also
match the configured market policy. Invalid bundles revert atomically. Price-free
operations such as cash withdrawals and FIFO harvest do not need reports.

## Accounts, resale and discovery

Read `accountOverview`, `externalAccountIdentity`, `accountTradeIds`, queue pages,
`tradeContext`, `ledgerState` and `rewardBacking` from the Diamond. Pages are bounded
at 64 entries and retain historical IDs. Claim pages can include consumed/paid
entries. Trade pages include settled trades. Inspect each returned record rather
than treating history length as active exposure.

The Statics module bridge is tracked by [Statics #143](https://github.com/EqualFiLabs/statics/issues/143).
Its proposed client ABI, canonical notifications, discovery and consumer handoff
require real source/deployment qualification. Existing finalized Genesis contracts
stay unchanged under [Statics #71](https://github.com/EqualFiLabs/statics/issues/71).
BucketPerps is not the activation registry consumer.

A permitted NFT transfer moves the entire account economically without moving its
tokens or rewriting the ledger. Statics-linked transfer restrictions still apply.
Unlinking must atomically checkpoint old weighted revenue and remove the seller's
boost prospectively. After a permitted sale, the buyer controls the account and can
relink under canonical Statics rules. Accrued revenue stays with the NFT. Raw stake
does not change when its multiplier changes.

Reward-only accounts remain nonempty even when wrapping and unwrapping are disabled.
Cash, live trades, queued and committed claims, unstaked/staked BPERP, effective weight
and accrued funded revenue prevent detaching the aggregate account leg. Unstaking
returns BPERP entitlement only; it does not release STATICS. There is no forced
forfeiture path for closing an NFT.

A structural NFT nonce cannot freeze external account mutations or global staking
accrual. Buyers should inspect current account state and receipts close to execution;
this interface does not add a marketplace or a sale authorization protocol.

## Units, fees and conversion

Prices and economic cash balances are WAD; leverage is an unscaled integer (100 means
100x). Token transfer inputs use native units where named `tokenUnits`. BPERP uses
the backing STATICS token's decimals and is held in protocol custody; wallet transfer
attempts revert. Account entitlements determine ownership.

A losing settlement uses the current flat reward rate, capped by unallocated backing.
Shortfalls are final, without IOUs. Fresh BPERP starts unstaked. Funded staking revenue
accrues prospectively; late stake cannot capture historical fees. Per-account fractional
remainders carry forward. Global index truncation remains funded rounding dust and is
not redistributed to a later denominator. Zero-weight staker fees remain house cash.

The launch asset is USDG. The fixed Dollar binding stays unset until
[Statics #142](https://github.com/EqualFiLabs/statics/issues/142) is implemented and
qualified. Binding and migration each require their exact scheduled payload. Successful
migration preserves WAD balances while changing physical transfer precision to USDstx.
USDG redemption requests must be representable at the original USDG precision; smaller
fractions stay credited and can be withdrawn as native USDstx. Failed quotes, fees,
health status or exact-transfer checks revert the complete operation.

## Operations and scoped safety actions

Pause mask bits are: opens 1, settlement 2, cash/revenue withdrawals 4, queue processing 8,
staking changes 16, reward issuance 32, fee delivery 64, conversion 128, deposits 256 and
surplus 512. Guardian or Governor can add pauses; only Governor removes them. A settlement
pause also blocks opens. Paused reward issuance skips rewards without blocking settlement.
Authenticated canonical callbacks remain available for atomic weight bookkeeping.

Safety hashes use `keccak256(abi.encode(tag, ...values))`, with the exact ABI types:

| Tag | Values | Typed execution |
| --- | --- | --- |
| `oracle` | address | `executeOracle` |
| `operator-router` | address | `executeOperatorRouter` |
| `conversion-flags` | bool, bool | `executeConversionFlags` |
| `wrap-capacity` | uint256 | `executeWrapCapacity` |
| `dollar-binding` | address, address, uint256 | `configureDollarMigration` |
| `dollar-migration` | address, address, uint256 | `migrateUsdGToUsdStx` |

Schedule with `scheduleSafetyAction`; execute after its stored readiness time. Cancellation
is explicit. Routine market, reward and surplus settings remain immediate. Delay changes
can be zero and do not rewrite readiness times already recorded. Conversion flag changes
do not reset capacity. Wraps consume capacity; unwraps replenish it only while both flags
are enabled, including unwraps of loss-issued BPERP.

`finalizeProtocol` permanently disables all general Diamond code installation. Typed
operational controls remain available, including the fixed Dollar capability. Finalization
must follow actual dependency and retained-capability qualification; test fixtures do not
establish production readiness.
