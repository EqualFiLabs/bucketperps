# Execution measurements

The execution measurement tests emit gas for cash and claim opens, loss close, zero-bounty claim bust, FIFO harvest and revenue claim. They use test NFT, token and oracle responses. They measure EVM execution in that fixture, excluding real Chainlink verification and billing, transaction calldata cost, target-chain inclusion, competition and failed attempts. Warm storage and pre-existing account state affect the readings.

The separately pinned oracle integration exercises unordered reports with a five-second delay and ten-second window as fixtures. These widths do not establish production availability, sequencer behavior, report licensing or execution profitability. Calibrating production risk and keeper settings requires target-chain measurements and the selected oracle market configuration. Zero funded bounty must continue to permit liquidation.
