# Bounded verification summary

The accounting and authority sources at revision `c1716778da8120b5fcf5c8fb829ef89ea218b80e` were exercised in a dedicated remote verification environment. Inputs and detailed artifacts are retained privately. This summary contains no proof inputs or credential information.

Solidity 0.8.33, Paris EVM and optimizer 200 were used. Halmos 0.3.3 ran against Foundry 1.8.6 output. Certora CLI 8.18.0 used its Solidity instrumentation with basic rule-sanity checks. Harness runtime SHA-256 identities were `c73a0097b157458a2fe190af8b5357f869339c32eed20503424e7c138bd513e1` for the Halmos transition harness and `80a47ab2f473af5376dd1dae3a2eb187fc2d141d52585435b3151f6c0490d925` for the Certora harness. These identify the respective verification binaries, not a deployed Diamond runtime.

| Tool | Property | Terminal result |
| --- | --- | --- |
| Halmos | Direct/FIFO payout never creates physical cash | Pass |
| Halmos | Selected claim consumption moves Q to D without cash | Pass |
| Halmos | Bounded FIFO harvest conserves cash and debt | Pass |
| Halmos | Fee funding cannot create cash or outrank queued debt | Pass |
| Halmos | Zero staking weight retains the staker slice in house cash | Pass |
| Halmos | Inventory caps issuance and retired trades cannot issue again | Pass |
| Halmos | Finalization cannot restore upgradeability through zero delays | Pass |
| Halmos | Unauthorized finalization reverts | Pass |
| Certora | Keeper payout is capped by funded protocol share and configured cap | Verified |
| Certora | Fee slices sum to the charged fee | Verified |
| Certora | Unauthorized finalization preserves state | Verified |
| Certora | Finalization irreversibly blocks the upgrade predicate | Verified |

The Halmos transition checks use 48-bit symbolic cash, debt and requested amounts, a single account/trade, one selected claim, at most two FIFO visits and a loop bound of two. Claim consumption starts with 100 debt units; reward issuance starts with 1,000 backing units. Cash quantum is one. Valid split assumptions and explicit seeded custody/queue/market state define the preconditions. External account callbacks and exact-transfer ERC20 behavior are modeled by deterministic harness contracts. Initial reverting setup paths were excluded from the terminal evidence only after correcting harness initialization and running reachable witness cases; all eight terminal checks have feasible successful paths.

Certora arithmetic uses 64-bit basis/margin/cap/funding inputs and 16-bit fee rates, with aggregate fee basis points at most 10,000. Finalization rules quantify the caller and initial protocol state. All four rules completed with reachable-state sanity witnesses. The configured loop bound is two with optimistic loop handling; these four rules contain no unbounded protocol traversal.

This is bounded evidence for the named production-library transitions and control predicates. It does not prove every settlement branch, arbitrary queue length, real external callback compatibility, oracle signatures or billing, token trust, target-chain economics or complete bytecode equivalence. Concrete settlement matrices, stateful tests and pinned dependency tests provide separate evidence. Statics account integration and future Dollar consumer behavior remain externally unqualified.
