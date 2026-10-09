# Sequencer Signal Deployment

This runbook deploys only the self-managed Robinhood sequencer signal. It does not deploy or
configure `StaticsOracle`. Testnet uses Ethereum Sepolia as the parent and Robinhood Testnet as
the child.

No command in this document should be run until the exact source commit, owner, observer set,
threshold, gas configuration, refund address, and funding plan have been reviewed. Deployment
keys, observer keys, relayer keys, RPC URLs, and observer API tokens never belong in the manifest
or repository.

## Deployment inventory

The minimum deployment contains:

- one `RobinhoodSequencerReporterL1` on Sepolia;
- one `RobinhoodSequencerAvailabilityFeed` on Robinhood Testnet;
- three independently operated observers with a two-signature threshold;
- one primary coordinator and one delayed backup coordinator; and
- one read-only monitor scheduled at least once per minute.

Use the official testnet sequencer feed at `wss://feed.testnet.chain.robinhood.com`. Use an
independent managed Robinhood RPC for each observer. The public RPC is suitable for initial
testing, not the production failure-domain design.

## Public deployment manifest

Copy `deployments/robinhood-testnet.example.json` to a deployment-specific JSON file. Before any
broadcast, replace the placeholders for:

- exact Git commit;
- L1 and L2 deployer addresses and reviewed minimum gas balances;
- owner and L2 refund address;
- sorted observer signing addresses and strict-majority threshold; and
- status gas limit, configuration gas limit, gas-price bid, and reserve-message count.

Leave contract addresses, transaction hashes, and code hashes `null` until those values exist.
The manifest contains public evidence only. Never add private keys, RPC URLs, or authentication
tokens. The checked-in example deliberately contains zero placeholders and cannot pass preflight
until it is copied and fully configured. Keep the deployment-specific copy untracked while
preflight and broadcast run from the exact source commit. Commit the completed public artifact in
a later evidence-only change after deployment.

Set the RPC URLs and manifest path through secret management, then run the read-only preflight:

```bash
cd observer
npm ci
SEQUENCER_DEPLOYMENT_MANIFEST=../deployments/robinhood-testnet.json npm run deployment:preflight
```

The preflight fails unless:

- the tracked checkout is clean;
- the checkout commit equals the manifest commit;
- both RPC chain IDs match the supported pair;
- the canonical delayed inbox has code;
- both deployers meet the reviewed minimum gas balances;
- the direct sequencer feed agrees with the independent Robinhood RPC; and
- the observer set is sorted, unique, at least three members, and uses a strict-majority threshold.

## Deploy the contracts

Use a Foundry keystore, hardware signer, or an approved signing process. Do not place raw private
keys in shell history. The repository scripts read public configuration from environment
variables and Foundry selects the signing account.

Deploy `RobinhoodSequencerReporterL1` on Sepolia with:

```text
SEQUENCER_SIGNAL_OWNER
SEQUENCER_SIGNAL_OBSERVERS
SEQUENCER_SIGNAL_THRESHOLD
SEQUENCER_L2_REFUND_ADDRESS
SEQUENCER_STATUS_GAS_LIMIT
SEQUENCER_CONFIGURATION_GAS_LIMIT
SEQUENCER_L2_GAS_PRICE_BID
```

Deploy `RobinhoodSequencerAvailabilityFeed` on Robinhood Testnet with:

```text
SEQUENCER_L1_REPORTER
```

The script entrypoints are:

```bash
forge script script/DeployRobinhoodSequencerReporterL1.s.sol:DeployRobinhoodSequencerReporterL1 --rpc-url "$ETHEREUM_RPC_URL" --broadcast --account <reviewed-keystore-account>
forge script script/DeployRobinhoodSequencerAvailabilityFeed.s.sol:DeployRobinhoodSequencerAvailabilityFeed --rpc-url "$ROBINHOOD_RPC_URL" --broadcast --account <reviewed-keystore-account>
```

Record both contract addresses and deployment transaction hashes in the manifest. Rerun the
preflight. With both addresses present it additionally verifies:

- runtime bytecode on the correct chains;
- L1 owner, inbox, child chain, refund address, gas configuration, threshold, and observers;
- the L2 feed's immutable L1 reporter binding; and
- that the reporter has not already been initialized.

It prints both runtime code hashes and the funding shortfall at the current retryable quotes. Copy
the code hashes into the manifest, add reviewed funding headroom for fee movement, and rerun the
preflight before initialization.

## Fund and initialize

`InitializeRobinhoodSequencerSignal.s.sol` funds the reporter and calls its one-time
`initializeL2Feed`. Its simulation fails unless the resulting pre-initialization balance covers
the initial configuration retryable plus at least four times the larger current status or
configuration quote. Funding and initialization may be separate broadcast transactions, so the
post-deployment smoke test rechecks the reserve against then-current quotes.

Configure:

```text
SEQUENCER_L1_REPORTER
SEQUENCER_SIGNAL_FEED
ROBINHOOD_CHAIN_ID=46630
SEQUENCER_REPORTER_FUNDING_WEI=<preflight fundingShortfall plus reviewed headroom>
SEQUENCER_RETRYABLE_RESERVE_MESSAGES=4
```

The initializer also requires the same `SEQUENCER_SIGNAL_OWNER`, observer set, threshold, refund
address, and retryable gas configuration used for reporter deployment. It rereads and compares
that complete reviewed configuration immediately before broadcast.

The broadcast account must be the current reporter owner. If the owner is a Safe, do not run the
EOA-oriented initialization script. Fund the reporter directly from an approved account, then
have the Safe call `initializeL2Feed(feedAddress)` on the reporter. Record the funding and
initialization transaction hashes in the manifest.

Confirm the retryable redemption on Robinhood Testnet. Initialization is not complete merely
because the Sepolia transaction succeeded. The L2 feed must show the expected observer-set
version, observer addresses, threshold, and impaired initial state.

## Start services

Install the package at `/opt/equalfi/statics-oracle`, create a locked service account named
`statics-oracle`, and place secret environment files below `/etc/equalfi/statics-oracle` with mode
`0600`. The systemd templates expect:

```text
observer-1.env
observer-2.env
observer-3.env
coordinator-primary.env
coordinator-backup.env
monitor.env
```

Each observer environment follows `observer/.env.example` and contains its own signing key,
distinct bearer token, independent RPC, host, and port. Bind the observer HTTP API to
`127.0.0.1`; never expose it directly on a public interface. Use an authenticated encrypted
transport between the coordinator and each host. The mainnet installation uses a mutual-TLS
Nginx server on each observer, a source-IP firewall rule, and three loopback-only Nginx
upstream proxies on the coordinator. Each proxy validates its observer server certificate,
while each observer validates the coordinator client certificate. The coordinator receives
only the ordered loopback proxy URLs and matching ordered token list. Set
`RELAYER_ROLE=primary` for the primary and `RELAYER_ROLE=backup` with
`BACKUP_DELAY_MS=45000` for the backup.

Copy the units from `observer/systemd/`, reload systemd, and enable the required instances:

```bash
systemctl enable --now statics-sequencer-observer@1.service
systemctl enable --now statics-sequencer-observer@2.service
systemctl enable --now statics-sequencer-observer@3.service
systemctl enable --now statics-sequencer-coordinator@primary.service
systemctl enable --now statics-sequencer-coordinator@backup.service
systemctl enable --now statics-sequencer-monitor.timer
```

Observers must be separated across operators, hosts, network paths, RPC providers, and key
custody. Running three unit instances on one host is acceptable only for disposable smoke testing,
not as evidence of independent operation.

## Post-deployment smoke test

After every observer reports three consecutive successes and the coordinators have delivered a
healthy L1 transition and L2 heartbeat, populate `monitor.env` with the two RPC URLs, manifest
path, observer URLs, and matching bearer tokens. Run:

```bash
cd observer
npm run deployment:smoke
```

Run the monitor on a coordinator host that already holds the ordered observer token set. Do not
copy quorum-wide observer credentials onto an additional monitoring host merely to run this check.

The smoke test fails unless it verifies:

- successful contract deployment and initialization transactions, including expected deployment
  senders;
- exact runtime code hashes;
- exact L1 and L2 contract bindings and configuration;
- synchronized observer-set versions and status sequences;
- all manifest observers reachable, healthy, and bound to the expected chains, contracts, and polling interval;
- direct-feed and independent-RPC block agreement;
- a healthy `latestRoundData` answer with more than ten minutes remaining on the lease; and
- at least four current maximum retryable quotes remaining in the reporter.

This proves a live testnet flow only. It is not production assurance or independent review.

## Monitoring

The timed monitor checks observer health, current RPC progress, contract state, and retryable
reserve every minute. It does not open a new sequencer-feed WebSocket on each run; the long-lived
observers check direct-feed and RPC agreement. The observer and coordinator each keep one feed
socket open. After a connection error, close,
or stale head, they wait five minutes before reconnecting and permit at most three connections
in a rolling hour. Invalid feed data and conflicting block hashes require operator review.
An observer stays impaired until three fresh samples succeed.

Route nonzero unit results and journal output into the chosen alerting system. Alert immediately on:

- any observer authentication or health failure;
- direct-feed and RPC disagreement;
- L1 and L2 observer-set or status-sequence mismatch;
- reporter balance below four current maximum retryable quotes;
- a warning at ten minutes or less remaining on the L2 lease and a failing monitor result at five minutes or less;
- any non-healthy availability answer or reason; and
- runtime bytecode or deployment-artifact mismatch.

Separately index `RetryableTicketCreated`, `ConfigurationApplied`, `L1StatusApplied`,
`HealthyLeaseRenewed`, and `HealthyLeaseInvalidated`. Alert when an L1 retryable does not produce
the corresponding L2 state change within the reviewed operational window.

## Failure drills

Complete and record all drills before using the signal as an oracle dependency:

1. Stop the primary coordinator and confirm delayed-backup renewal.
2. Stop one observer and confirm the two-of-three quorum remains live while monitoring alerts.
3. Stop two observers and confirm the lease expires without a marking transaction.
4. Break one observer's RPC and confirm it becomes impaired after three samples.
5. Delay or omit a retryable redemption and exercise owner-only requeue.
6. Restore services and confirm three-success recovery, a new status sequence, a fresh heartbeat,
   and the consumer recovery boundary.
7. Rotate one observer through the owner process and confirm fail-closed configuration delivery.

If the deployment behaves unexpectedly, stop both coordinators. Do not lower the quorum threshold.
The existing lease expires automatically. The contracts are non-upgradeable; a contract defect
requires a reviewed replacement deployment rather than an in-place upgrade.

## Explorer verification and handoff

Verify both contracts against their recorded compiler, optimizer, source commit, constructor
arguments, and chain explorer. Archive:

```bash
forge verify-contract <reporter-address> src/RobinhoodSequencerReporterL1.sol:RobinhoodSequencerReporterL1 --chain-id 11155111 --constructor-args <exact-abi-encoded-constructor-arguments>
forge verify-contract <feed-address> src/RobinhoodSequencerAvailabilityFeed.sol:RobinhoodSequencerAvailabilityFeed --chain-id 46630 --rpc-url "$ROBINHOOD_RPC_URL" --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api/ --constructor-args <exact-abi-encoded-constructor-arguments>
```

Use the constructor arguments from the reviewed broadcast artifact, not a reconstructed or
hand-edited value. Confirm the explorer reports the same compiler version, optimizer settings,
constructor arguments, and runtime code hash before recording source verification as complete.

Archive:

- the completed public manifest;
- deployment and initialization transaction receipts;
- runtime code hashes;
- exact Foundry and compiler versions;
- observer-set hash and custody assignments;
- preflight and smoke output;
- failure-drill evidence; and
- independent review results.

Do not set `config/robinhood-mainnet.assets.json` sequencer fields to verified and do not deploy the
full Statics Oracle until the separate mainnet deployment and production gates have passed.
