# Dependency evidence and remaining qualifications

| Dependency | Source pin | Evidence | Remaining requirement |
| --- | --- | --- | --- |
| Execution oracle | EqualFiLabs/statics-oracle `7f3b51ebabe04023ee724452078b86c8fe31b2c0` | Actual adapter source executes through the Diamond: eight-decimal normalization, unordered report windows, owner settlement and consumer rejection. The client re-exports its actual pinned interface. | Chainlink signature verification and billing, deployed consumer/stream configuration, sequencer behavior and report timing on the target chain. |
| Operator router | EqualFiLabs/operator-fee-router `09250b7b30b2a6d8fbe7007ca11f2f6708f866ae` | Actual router bootstraps all 5,555 IDs, receives exact funded contributions, and pays the entitled owner. | Target deployment identities, canonical Genesis/activation state and enabled settlement asset. |
| Statics account bridge | Proposed client ABI; [#143](https://github.com/EqualFiLabs/statics/issues/143) | Current-owner, lifecycle, callback rollback and revenue tests use explicit fixtures. | Actual bridge, authenticated module discovery, registration disablement, every canonical weight transition and existing activation-consumer handoff. No matching implementation PR was available at inspection. |
| Statics Dollar | Pegged ABI observed at EqualFiLabs/statics `09f3612ecf20c5f2b077818655ec51cf543dada6` | Exact WAD conversion and redemption are tested using a consumer fixture. | [#142](https://github.com/EqualFiLabs/statics/issues/142) approved-consumer quotes/mint/redemption semantics, deployed token/core/profile and healthy exact redemption. Keep the binding unset. |

The adapter/router sources are pinned submodules. They compile here with Solidity
0.8.33, Paris and 200 optimizer runs. This exercises their source with BucketPerps;
it does not establish equality with separately deployed builds or their own release
compiler settings. The oracle verifier and sequencer are explicit fixtures. Router
Genesis identities are explicit fixtures. None of these tests executes a live-chain
transaction or qualifies a deployed Chainlink verifier.

The oracle has absolute source imports; explicit import mappings resolve its helper
paths. Its public client ABI is imported directly from the pinned dependency. No
licensed report payload or credential is included in this repository.

Statics #143 must preserve finalized Genesis contracts under
[#71](https://github.com/EqualFiLabs/statics/issues/71). In particular, attaching an
external account leg and canonical registration must agree on callback ordering;
canonical notifications must cover initially boosted stake, link/unlink, activation,
recovery and reset atomically. Mocks do not settle this compatibility requirement.

Configuration fixtures are not production qualification. Launch/finalization decisions
must use the exact candidate, dependency revisions, deployed code identities and
chain-specific evidence. Missing external implementations remain unresolved rather
than being treated as a passing mock integration.
