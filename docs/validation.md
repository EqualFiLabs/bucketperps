# Candidate validation

The complete implementation includes Diamond routing and irreversible finalization, current-owner Position NFT accounts, independent oracle submission, cash and FIFO claim trading, hard-bust liquidation, funded fee accounting, backed BPERP loss rewards, prospective staking revenue, scoped controls, fixed future Dollar conversion, client views and atomic deployment preparation.

The accumulated CI-profile suite passes 206 tests across 46 suites. Fuzz tests use 4,096 runs; the accounting state machine completes 256 runs at depth 128 with no handler reverts. The production bootstrap installs fourteen facets with 66 unique selectors, checked against compiler method identifiers. Production contract size checks pass under Solidity 0.8.33, optimizer 200 and Paris EVM.

Coverage includes the twenty independent ledger vectors, cash/claim settlement and FIFO tombstones, approved price arithmetic vectors and sampled differential comparisons, exact bust boundaries, zero-bounty liquidation, receipt backing and inventory exhaustion, every public conversion flag combination, prospective revenue and canonical callback fixtures, NFT resale and approval rejection, dependency failure rollback, scoped pauses, finalized retained controls and fixed migration rollback, and exact Dollar quotes at healthy non-dollar collateral oracle prices. Pinned oracle and Operator implementations are exercised separately from their external fixtures. The bounded verification summary describes the named remote properties and assumptions.

# Remaining qualification

The implementation is a review candidate. Statics issue #143's actual lifecycle bridge, discovery and complete canonical multiplier transition set are not qualified. The oracle integration uses a test verifier and sequencer, and does not prove real Chainlink signature verification, billing, licensing or target-chain market configuration. The Operator integration uses test Genesis identities. Dollar issue #142's approved-consumer fee exemption remains unimplemented in the inspected dependency source; keep migration unbound.

Immediate orders currently consume the oracle's delayed reference price. Known-price latency exposure remains unresolved; source integration and positive fixture payouts do not qualify production execution safety. Selecting a compatible execution policy requires an explicit design decision.

Production reward rates and taper dates, inventory budget, risk limits, keeper settings, surplus split and safety delays remain unselected. Development numeric examples are configurable parameters. Execution measurements exclude target-chain inclusion, external verification charges and off-protocol hedging costs. Sampled arithmetic comparisons do not establish exhaustive equivalence to the recovered reference.

No deployment, live transaction, protocol finalization or merge is part of this validation. Source integration, local tests, remote bounded verification and production deployment are distinct evidence categories.
