# Execution oracle integration

The client ABI is pinned to EqualFiLabs/statics-oracle revision `7f3b51ebabe04023ee724452078b86c8fe31b2c0`. The execution result contains, in order, `uint256 price1e18`, `uint32 referenceTimestamp`, `uint32 validFromTimestamp`, `uint32 observationsTimestamp`, and `bytes32 streamId`. Prices are positive normalized WAD values; the client additionally enforces its arithmetic domain.

The oracle authenticates every supplied signed report, selects the unique matching report independently of bundle order, checks its configured stream and time window, enforces sequencer health, and owns verifier billing. BucketPerps forwards caller-supplied report bundles unchanged. BucketPerps does not implement Chainlink decoding or a second report-selection policy.

The BucketPerps Diamond must be an authorized oracle consumer. That application-level authorization grants no trade authority to a report supplier. Owners can submit directly using reports they lawfully obtain; our frontend or report service is optional. This does not grant access to our licensed subscription or permission to redistribute its reports. Reports must satisfy the oracle's configured market and stream requirements.

Oracle identity is configured once at bootstrap; any future replacement uses the scoped protocol dependency controls. Markets bind the intended stream identity. Cash withdrawals, queue harvest and account cleanup do not request execution prices.

The source pin establishes the ABI, not deployed or end-to-end compatibility. Local client tests use an adapter fixture. Real verifier authorization, billing, stream coverage, timing, sequencer operation and deployed source identity remain integration gates.
