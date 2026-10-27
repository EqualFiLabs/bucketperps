# Mathematical reference

The economic baseline is Papertrade contract set 2 (2026-10-21). The reference
identity is the [Exchange implementation](https://hyperevmscan.io/address/0x0A44049dBbb6b4762a6ba37aa0f7548c0B4A3723#code)
and its linked pricing runtime. Original Solidity source was unavailable;
arithmetic was reconstructed from executable bytes. These are reference identities,
not deployment addresses or dependencies of BucketPerps.

| Input | SHA-256 of runtime bytes |
| --- | --- |
| Exchange, 23,959 bytes | `fc7374f3969381160732fe98c5e3145e00c3f167f168d61d65bb4972e9a6b268` |
| Linked pricing library, 6,286 bytes | `ced8e434ebd5379c4acc1fba809a5b18f531c676a264308c9a0a1a76d9641440` |

The reviewed reconstruction snapshot has SHA-256
`6bd67602c3223812d0a36e1b26b72b59c2d0325fb1a033df07858dca1f4491bc`.

The reference selectors are `0x50c23fab` (stored-position threshold),
`0x06c5308a` (directional PnL) and `0xb67f3dd7` (winning impact).
The reference ABI uses uint64 prices, uint128 margin, uint32 integer leverage,
and uint64 WAD liquidation buffer. Impact coefficients and reference notional
are uint256. Test values do not establish production price units, instrument
configuration, or acceptable deployment parameters.

## Hard-bust threshold

For entry E, integer leverage L and liquidation buffer B scaled by 1e18:

```
distance   = floor(E / L)
boundary   = long ? E - distance : E + distance
adjustment = floor(boundary * B / 1e18)
threshold  = uint64(long ? boundary + adjustment : boundary - adjustment)
```

The caller obtains B as `uint64(instrumentWord >> 120)`. It is separate from
trading fees and liquidation charges. Five basis points is 5e14, not 5e16.
Keep both divisions and compute the adjustment from boundary. Zero leverage
produces Solidity panic 0x12; short subtraction can panic 0x11. Intermediate
arithmetic is checked. The final explicit narrowing conversion truncates to
64 bits; it is not a SafeCast. Validation of admitted trading terms belongs at
the protocol boundary rather than changing this reference behavior.

For E=1,000,000,000, L=100 and B=5e14 the long threshold is 990,495,000 and
the short threshold is 1,009,495,000. At L=1,000 these become 999,499,500 and
1,000,499,500. These are development examples, not approved leverage settings.

## Favorable-PnL integer pipeline

1. Subtract floor(entry/50,000) from favorable integer movement, clamping its
   effective mark to entry inside that dead zone. Adverse movement is unchanged.
2. Compute signed raw PnL as margin * integer leverage * directional movement /
   entry, with checked multiplication and signed division toward zero. Negative
   adjusted PnL is capped at negative margin.
3. Inside the selected band, use the original integer holdback order. Standard
   band endpoints are floor(entry*75/1e6) and floor(entry*600/1e6), coefficient
   3.597e18. The alternate endpoints use 30 and 1,000, coefficient 6.085e18,
   and one extra `(1-u)` factor. Exact endpoints take the ordinary impact path.
   This block uses wrapping uint256 arithmetic; zero carved movement is a
   sentinel for the ordinary impact path.
4. For effective fractional movement m scaled by 1e18, compute dR=floor(m*R/1e18)
   and dP=floor(1e6*m*P/1e18). The respective impact terms are floor(1e36/dR)
   and floor(N*1e18/dP). Zero denominators use max-uint sentinels. If either
   impact exceeds 1e36, return zero. Otherwise compute retained fraction as
   floor((1e18-base)*1e18/(1e18+impactR+impactP)), then multiply signed profit
   by that fraction and divide by 1e18. Operations outside the holdback block
   remain checked, including their early-return ordering.

BucketPerps deducts its separate 1.90% winning fee after this adjustment.
Cash-quantum rounding is a subsequent accounting step. Neither belongs inside
the recovered pricing reference.

## Reproducible examples and evidence limits

The pricing fixture contains 24 threshold cases and 156 PnL cases. `args` is ABI
encoding in the argument order below; `output` is the complete reference return
or revert data. `success` distinguishes the two. IDs remain stable.

- Threshold: `(uint64 entry, uint32 leverage, uint64 bufferWad, bool isLong)`.
- PnL: `(uint64 entry, uint64 mark, uint128 margin, uint32 leverage, bool isLong,
  uint256 base, uint256 rateMultiplier, uint256 positionMultiplier,
  uint256 referenceNotional, bool alternateCurve)`.
- Successful threshold output: one uint64 ABI word.
- Successful PnL output: `(int256 rawPnl, int256 adjustedPnl)`.

Examples include favorable and adverse moves, both curve modes and directions,
tiny prices, integer neighbors of dead-zone/band edges, zero denominators,
checked failures and final threshold truncation. They were executed against
original runtime bytes and compared to the reconstruction before inclusion.

The separately recorded PnL campaign matched success/revert status and exact
output bytes for 81,920 fuzz comparisons across two seeds and 8,198 deterministic
comparisons. The threshold was additionally compared for 4,096 full-width fuzz
inputs. This is finite local execution evidence. It establishes neither exhaustive
equivalence nor original-source recovery, current live-code authentication,
production configuration validity, or external integration readiness.

The reference ABI width must not be used to silently truncate 18-decimal oracle
prices. BucketPerps uses uint256 prices normalized to 18 decimals and omits the reference's
final narrowing. This is an explicit adaptation, not byte-for-byte equivalence.

The implementation accepts positive prices through uint120.max and notional
through uint128.max. Leverage is a uint32 integer; base rate is at most WAD, each
multiplier at most uint96.max and reference notional at most uint128.max. These
are technical bounds, independent of much smaller calibrated market limits.
Zero thresholds and thresholds at or past entry retain the recovered formula's
result without an added admission rejection. Intermediate floors remain distinct;
full-precision multiplication/division supports the widened products. There is
no wrapping arithmetic in the admitted implementation domain.

Implementation tests compare golden outputs in their shared admissible domain.
A separate offline comparison also matched the original runtime for 4,096 cases
each of general PnL, favorable PnL and usable thresholds. Those 12,288 comparisons
executed the Paris-target production harness in a Shanghai-capable local EVM
required by the original runtime. Wider-domain gain bounds, favorable
monotonicity and inclusive bust boundaries are separate fuzz properties.
Original invalid configurations and truncating outputs are not presented as
equivalent to the intentionally bounded, widened implementation.
