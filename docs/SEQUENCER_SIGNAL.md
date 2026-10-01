# Robinhood Sequencer Availability Signal

This repository provides a reusable, self-managed availability signal for Robinhood Chain.
Consumers use the Chainlink uptime-feed convention:

```text
answer = 0: healthy
answer = 1: unavailable
```

The signal is not operated by Chainlink or Robinhood and does not prove transaction inclusion.
It combines two independent safety properties:

1. Ethereum records quorum-attested status transitions in canonical L1 order.
2. Robinhood requires a renewable heartbeat lease to prove that the observer and relay path is live.

The L2 feed reports healthy only while both properties are true.

## Failure model

Each observer samples Robinhood's direct sequencer WebSocket and an independent Robinhood RPC
every 30 seconds. A new process starts in `UNKNOWN`. Three consecutive successful samples move
it to `HEALTHY`; three consecutive failures move it to `IMPAIRED`; and recovery requires three
new consecutive successes.

At least three independently operated observers are required. The threshold must be a strict
majority. Each operator uses a separate host, network path, RPC provider, and EIP-712 key.

When a quorum's confirmed state differs from Ethereum, observers sign one transition report.
Any relayer may submit that report to `RobinhoodSequencerReporterL1`. The reporter validates
membership, ordering, freshness, and quorum, then creates an Arbitrum retryable ticket to the
Robinhood feed. The reporter is prefunded, so the submitting relayer pays only L1 transaction
gas while the reporter pays the retryable submission and L2 execution fee.

While observers are healthy, they also sign an L2 heartbeat every five minutes. Each accepted
heartbeat lasts at most 15 minutes. If signing, coordination, RPC access, or L2 relay stops, the
lease expires without a marking transaction.

If Robinhood block production freezes, its timestamp cannot advance and no Robinhood contract
can act during the freeze. Ethereum can still record the impairment. When Robinhood resumes,
the queued L1 impairment arrives and the old heartbeat is expired. The consumer's recovery
grace starts only after a later effective recovery on L2.

## Contracts

`RobinhoodSequencerReporterL1.sol` is deployed on Ethereum Mainnet or Sepolia. It:

- owns the authoritative observer set;
- accepts only fresh, transition-only, sequential quorum reports;
- starts impaired and fails closed during observer rotation;
- creates retryable tickets through the chain-specific delayed inbox;
- retains accepted transitions and can requeue an exact missing status sequence or configuration through Safe-only functions;
- has explicit retryable gas and refund configuration; and
- disables ownership renunciation.

`RobinhoodSequencerAvailabilityFeed.sol` is deployed on Robinhood Mainnet or Testnet. It:

- has no owner or independent administration;
- accepts configuration and status only from the aliased L1 reporter;
- ignores duplicate or stale cross-chain messages and rejects sequence gaps;
- verifies sorted heartbeat signatures and recent canonical block hashes;
- expires heartbeats after at most 15 minutes; and
- exposes `UNINITIALIZED`, `HEALTHY`, `L1_REPORTED_IMPAIRED`, or `LEASE_EXPIRED` diagnostics.

Supported pairs are:

| Ethereum parent | Robinhood child | Delayed Inbox |
| --- | --- | --- |
| Mainnet `1` | Mainnet `4663` | `0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D` |
| Sepolia `11155111` | Testnet `46630` | `0xF2939afA86F6f933A3CE17fCAB007907B6b0B7a4` |

## Service operation

The observer exposes:

- `GET /health`, including state and consecutive sample counters;
- `POST /status` for an L1 status proposal; and
- `POST /heartbeat` for an L2 heartbeat proposal.

It refuses to sign while unknown, rejects proposals that disagree with local state, and checks
the current onchain version and sequence immediately before signing.

The coordinator polls every 30 seconds. It gathers status signatures when the L1 state differs
from observer consensus and gathers heartbeat signatures when ten minutes or less remain. It
recovers and sorts authorized signers, simulates each contract call, submits one transaction,
and waits for the receipt. A backup coordinator can use `RELAYER_ROLE=backup` and a delay so it
acts only if the primary update is still absent.

Install and test:

```bash
cd observer
npm ci
npm run check
npm test
```

Copy `.env.example` into secret management. Never commit observer keys, relayer keys, or RPC
URLs.

## Deployment sequence

Deployment is not part of repository implementation. Before broadcast:

1. Review bytecode, observer operators, threshold, Safe, refund address, and gas limits.
2. Deploy and fund the L1 reporter on Ethereum.
3. Deploy the L2 feed with the reporter address.
4. Call `initializeL2Feed` on the reporter, which queues the initial impaired configuration.
5. Confirm the configuration retryable is redeemed on Robinhood.
6. Start observers and wait for three successful samples on each required signer.
7. Start the primary coordinator and at least one delayed backup.
8. Confirm the L1 healthy transition, its L2 redemption, and an accepted heartbeat.
9. Configure Statics only after independent review and a chosen recovery grace period.

The L1 deployment script requires:

```text
SEQUENCER_SIGNAL_OWNER
SEQUENCER_SIGNAL_OBSERVERS
SEQUENCER_SIGNAL_THRESHOLD
SEQUENCER_L2_REFUND_ADDRESS
SEQUENCER_STATUS_GAS_LIMIT
SEQUENCER_CONFIGURATION_GAS_LIMIT
SEQUENCER_L2_GAS_PRICE_BID
```

The L2 deployment script requires `SEQUENCER_L1_REPORTER`.

## Monitoring

Alert on:

- observer state disagreement or missing quorum;
- three-failure impairment or three-success recovery;
- retryable creation, redemption failure, expiry, or manual requeue;
- L1 and L2 observer-set or status-sequence lag;
- reporter balance below four quoted messages;
- heartbeat time remaining below ten minutes and urgently below five minutes;
- any availability reason change;
- direct feed and RPC hash disagreement;
- stale or future-dated heads; and
- ownership, gas configuration, refund address, or observer-set changes.

## Incident response

Observer rotation is a Safe action on L1. It immediately records an impaired state, increments
the status sequence, replaces the observer set, and queues the new configuration. Do not lower
the threshold to preserve liveness. Prepare new operators first, rotate, confirm L2 redemption,
then re-establish health through three successful samples and a new transition.

If a retryable is not redeemed, the Safe can requeue the exact missing status sequence or the
latest configuration after funding and gas parameters are checked. Historical status retention
allows sequence gaps to be filled in order. These methods are not public because arbitrary
retries could drain the prefunded reporter.

## Known limits

- The signal observes production and agreement, not inclusion fairness.
- A strict-majority observer compromise can falsely report status or renew a heartbeat.
- The Ethereum Safe controls observer membership and retryable configuration.
- Shared hosting, DNS, RPC, or custody can collapse nominally independent failure domains.
- A frozen L2 cannot advance time or execute a local down-marking transaction.
