# Client event reference

Read events from the BucketPerps Diamond. They describe completed atomic transitions;
reverted calls leave no events or partial accounting. Token mint/burn events originate
from BPERP, and backing releases originate from its fixed vault.

| Events | Meaning |
| --- | --- |
| Deposited / Withdrawn / UsdGWithdrawn | Account cash enters or exits custody; amounts distinguish token units and WAD. |
| AccountActivityChanged | The aggregate external Statics leg attaches or detaches. This is not a financial snapshot nonce. |
| TradeOpened / TradeSettled | Trade ID, NFT, funding source, immutable economic version and full settlement result. |
| ExecutionPriceAccepted | Accepted market/stream, WAD price and oracle report timestamps. Signed report bytes are not duplicated in logs. |
| ClaimQueued / ClaimConsumed / ClaimHarvested | Follow debt creation, consumption and FIFO cash credits using the emitted IDs. Historical tombstones remain discoverable. |
| FeesAllocated | Quoted versus funded fees, actual slices and zero-weight staker retention. A waived fee creates no later payable. |
| KeeperCreditAllocated | Funded protocol fees reclassified to the executing keeper. |
| RewardInventoryFunded / LossRewardIssued | Backing funding, settlement loss basis, current rate, requested/issued units and permanent shortfall. |
| StakeChanged / StakerRevenueIndexed / StakerRevenueClaimed | Prospective weight, funded global accrual and account cash credits. |
| CanonicalWeightChanged | Authenticated Statics checkpoint; past accrual uses the prior weight. |
| OperatorFeesDelivered / ProtocolFeesWithdrawn | Funded liabilities leave settlement custody. |
| Wrapped / Unwrapped | Existing STATICS backing enters or exits; neither operation changes STATICS supply. |
| PauseChanged / SafetyActionScheduled / SafetyActionCancelled | Operation mask and exact delayed payload state. |
| ConversionFlagsChanged / WrapCapacityChanged | Independent conversion flags and explicitly set remaining capacity. |
| OracleChanged / OperatorRouterChanged | Typed dependency binding changes. |
| DollarMigrationConfigured / SettlementAssetMigrated | One fixed Dollar binding and exact one-way physical denomination change. |
| ProtocolFinalized | General code installation is permanently unavailable. |
| SurplusConfigured / SurplusDistributed | Current split and realized house cash distribution. |

Use transaction receipts and bounded state views together. NFT transfer logs alone do
not capture external account mutations or global staking-index changes. A successful
transaction may issue fewer loss rewards than requested, including zero; index the
shortfall rather than reconstructing an IOU.
