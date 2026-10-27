# Statics account boundary

The inspected public Statics revision is
`03c6d23cd8207c6f69b6b9a53b56f103c30ee52c`. Financial authority uses the standard
ERC-721 `ownerOf(uint256)` call at the canonical PositionNFT address. It never
uses token approval, operator approval, cached ownership or the approval-aware
Statics financial helper.

At that revision, PositionNFT close/burn checks initializing state, active legs,
unresolved obligations and the applicable Morpho account guard. The internal
leg namespace includes module authority, module type and local identifier.
External callers have no public attach/detach bridge. Module-assisted creation
is Diamond-self-only. Ordinary paid NFT creation remains available.

[Statics #143](https://github.com/EqualFiLabs/statics/issues/143) tracks the
missing bridge, canonical multiplier checkpoints and module discovery.
The external-account interface in this repository is a proposed client ABI,
not an assertion that that revision implements it. Its calls derive module
authority from the calling BucketPerps Diamond and use one fixed module type
with the NFT ID as local account ID. New registration must reject initializing
and nonexistent NFTs. Disabled registration must preserve existing protection
and safe module-only detach. Callback names, selectors, code identity and every
canonical transition require qualification against the actual implementation
before production configuration. Mocks do not satisfy this gate.

The entire BucketPerps account follows permitted NFT transfers without moving
custody or ledger entries. Existing Genesis-linked transfer restrictions stay
in force. A nonempty cash, trade, live/committed-claim, reward, stake or revenue
balance keeps the aggregate leg attached. Cleanup clears only BucketPerps' own
leg after every category is empty. Neither an owner nor ERC-721 approval can
force-detach it through BucketPerps.

Finalized Genesis collection, registry, vault and distributor contracts remain
unchanged under [Statics #71](https://github.com/EqualFiLabs/statics/issues/71).
Activation notifications must reach the Statics Diamond through its qualified
consumer handoff. BucketPerps is not the registry consumer. Boosted staking
remains gated until actual prospective checkpoint coverage is established.
