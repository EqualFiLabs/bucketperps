# Cash and debt reference

The ledger fixture defines independently specified before/after states in WAD.
It is an acceptance oracle for the production book, not evidence that production
settlement or FIFO processing is implemented.

| Symbol | Meaning |
| --- | --- |
| T | Accounted settlement-token custody |
| C | Withdrawable account cash |
| M | Cash margin locked in trades |
| F | Funded fees, staking revenue and keeper payables |
| H | House cash: T - C - M - F |
| S | FIFO-earmarked cash, a subset of H |
| Q | Live FIFO debt |
| D | Claim debt committed to open trades |
| P | Signed realized house PnL, independent of payout timing |

The mandatory cash equality is T=C+M+F+H, with 0<=S<=H. Debt is not custody.
For the modeled trade/debt/payout operations, the change in H-Q-D equals the
change in P. External reserve funding and separately classified donations can
change this offset without being trading PnL.

A win recognizes `-(net profit + actually funded fees)` in P. A loss recognizes
`loss - actually funded fees`. Claim principal is not a second winning profit.
Cancelled claim debt can improve P and net equity without producing any cash.
Harvest, claim consumption, funded-fee delivery and fee-to-cash credits do not
recognize the trade again. Surplus distribution decreases cash and P once.

For example, a $100 cash margin winning $100 adjusted profit with no house cash
returns $100 principal, queues $98.10 net profit, funds no fee and changes P by
-$98.10. The $1.90 deduction creates no recipient IOU. Later harvest funds that
same debt without changing P again.

When stake weight is zero, the staker slice stays in H instead of becoming F.
For an otherwise fully funded $100 gain, the trader still receives $98.10 profit,
but only $0.90 becomes payables. House P changes by -$99.00; the retained $1.00
creates no historical entitlement. This also applies to the staker slice of an
eligible cash loss or cash liquidation fee.

Twenty transitions cover queued and funded cash wins, zero-weight retention,
cash losses while FIFO is active, claim consumption, cancelled claim losses,
claim survivor-plus-fee funding boundaries, partial claim-win funding, claim
busts with zero cash gain, S-first harvest, residual S release, fee payments and
surplus recognition. Fixture fees use the approved 190/200 bps allocation;
numerical settings remain configurable development values until calibrated.
