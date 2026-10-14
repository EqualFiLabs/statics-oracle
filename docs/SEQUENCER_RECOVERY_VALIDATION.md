# Sequencer recovery validation

On 2026-10-09, the focused recovery checks passed without sending a mainnet transaction or
interrupting the live observer and coordinator services.

- `test_LeaseExpiryRecoveryBlocksPricesForOneHour` uses the production feed and oracle
  contracts with a local two-of-three observer set. It renews heartbeats, lets a lease expire,
  confirms prices fail closed, submits a fresh quorum heartbeat, and checks that strict pricing
  remains blocked through the 3,600-second recovery boundary and resumes one second later.
- `test_DeployedFeedLeaseExpiryBlocksPrices` forks Robinhood mainnet at block `84,486,562` and reads
  the deployed feed at `0xeCe3F60De85705472292a44787123a8Fc46CDa54`. It confirms the
  live healthy answer, advances fork time to the recorded lease expiry, then confirms the feed
  reports unavailable and `StaticsOracle.priceUsd` reverts with `SequencerDown`.
- The US Central coordinator's monitor service last completed successfully at 2026-10-09
  21:51 UTC. Its monitor mode checks deployed runtime code hashes and bindings, observer health,
  L1/L2 state agreement, reporter retryable reserve, and remaining heartbeat lease.

The fork check uses deployed mainnet feed state but does not submit a recovery heartbeat to
mainnet. The quorum recovery and one-hour price boundary are exercised with local test keys.
The manifest records `sequencer.verified: true` and `gracePeriod: 3600` based on the live
monitor checks and the focused recovery tests above. This is operational verification of the
self-managed signal, not an external audit certification.
