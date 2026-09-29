# Robinhood Sequencer Availability Signal

This repository provides a reusable observed-availability signal for Robinhood Chain. It is
designed for any Robinhood application that can consume the Chainlink
`AggregatorV3Interface` uptime convention:

```text
answer = 0: quorum recently observed healthy block production
answer = 1: no active quorum-backed healthy lease
```

The signal is self-managed. It is not operated by Chainlink, is not a canonical Robinhood
feed, and does not prove that every account or transaction can reach the sequencer.

## Failure model

At least three independent observer operators are required. The onchain threshold must be a
strict majority. Each observer uses its own:

- direct Robinhood sequencer-feed connection;
- independent Robinhood RPC connection;
- EIP-712 signing key; and
- host, network, and monitoring stack.

Every 30 seconds, a coordinator proposes a recent block behind the direct feed head. Each
observer independently receives a fresh message from Robinhood's sequencer feed, verifies that
feed block against its independent RPC, and checks the proposed block through the independent
RPC. The observer signs only if both sources are recent and consistent, the observer is still
in the onchain set, and the proposed lease is safe.

[Robinhood documents the direct feed](https://docs.robinhood.com/chain/connecting/) as
`wss://feed.mainnet.chain.robinhood.com`. This is distinct from the HTTPS sequencer transaction
submission endpoint. The observer checks feed-message progression and confirms the feed's block
hash through its independent RPC.

Any coordinator can collect the signatures and relay them. The relayer is not trusted for
safety. The contract independently verifies signer authorization, strict-majority quorum,
signature uniqueness and order, observer-set version, the recent block hash, and the lease
limit.

An accepted observation grants a healthy lease for at most 95 seconds. With 30-second polls,
failed rounds at approximately 30, 60, and 90 seconds leave the lease to expire at 95 seconds.
No transaction is needed to change the read result from up to down.

The contract accepts observations no more than 240 blocks behind the submission block. This
stays inside the EVM's 256-block `blockhash` window and allows roughly 24 seconds at the
observed September 2026 Robinhood cadence of about 10 blocks per second. Operators must alert
before signing and relay latency approaches that limit.

If block production stops completely, the chain timestamp also stops. No onchain mechanism
can record or act on the outage while the chain is frozen. On the first block after recovery,
the old lease is expired. The signal reports down until a new quorum observation is submitted,
then consumers enforce their configured recovery grace period. This prevents a protocol action
from using the last pre-outage healthy state during recovery.

## Components

`RobinhoodSequencerAvailabilityFeed.sol` is the non-upgradeable feed contract. It exposes:

- `latestRoundData()` with the standard uptime answer convention;
- `healthyUntil`, `recoveredAt`, and last-observation diagnostics;
- a permissionless `submitObservation` relay path;
- two-step ownership and observer rotation; and
- automatic lease invalidation when the observer set changes.

`observer/src/observer.mjs` is the signing service. It exposes:

- `GET /health`; and
- `POST /observe` with `{ "observation": ... }`.

`observer/src/coordinator.mjs` polls every 30 seconds, requests signatures, verifies recovered
signers against the onchain set, sorts the quorum, simulates the submission, and relays it.
Multiple coordinators may run concurrently because submission is permissionless.

## Deployment policy

Deployment is intentionally separate from implementation. Do not configure Statics or another
consumer until all of the following are reviewed:

1. Contract bytecode matches the reviewed source and was deployed on chain ID `4663`.
2. Owner is a reviewed Safe or equivalent controlled account.
3. Observer addresses are sorted, independently operated, and use separate keys.
4. Threshold is a strict majority. The minimum supported configuration is 2 of 3.
5. Every operator uses genuinely independent RPC infrastructure.
6. Alerting and replacement procedures have been exercised.
7. The consuming protocol's post-recovery grace period has been selected.

The deployment helper reads these variables:

```text
SEQUENCER_SIGNAL_OWNER
SEQUENCER_SIGNAL_OBSERVERS      comma-separated, ascending address order
SEQUENCER_SIGNAL_THRESHOLD
```

Run the normal Foundry simulation and bytecode review before any broadcast. The repository does
not contain or create deployment keys.

## Observer operation

Install and test the service:

```bash
cd observer
npm ci
npm run check
npm test
```

Copy `.env.example` into the operator's secret-management system. Do not commit `.env`, RPC
URLs, observer keys, or relayer keys. Start one observer per independent operator:

```bash
node src/observer.mjs
```

Start one or more replaceable coordinators:

```bash
node src/coordinator.mjs
```

Place observer endpoints behind TLS, request-size limits, and rate limiting. Network access may
be restricted to known coordinators as a denial-of-service precaution, but safety must not
depend on that restriction. An observer validates every proposal before signing.

## Monitoring

Alert on:

- `healthyUntil - current chain timestamp` below 60 seconds;
- two consecutive failed coordinator rounds;
- any expired lease;
- direct and reference RPC hash disagreement;
- stale or future-dated RPC heads;
- observer-set or ownership changes;
- signer authorization failures; and
- a recovery observation, which starts the consumer grace period.

Monitor each observer independently. A green coordinator alone is not evidence that independent
observers or independent RPC paths are healthy.

## Rotation and incident response

`setObserverSet` invalidates an active healthy lease immediately. Prepare the new operators and
coordinator configuration before rotation, execute the owner transaction, then obtain a new
quorum observation. Consumers will remain unavailable throughout their recovery grace period.

If an observer key may be compromised, rotate the complete reviewed set. Do not lower the
threshold to preserve liveness. If the owner is compromised, consumers should remove or replace
the feed according to their own governance process.

## Known limits

- The signal observes block production and agreement, not transaction inclusion fairness.
- A strict-majority observer compromise can falsely renew health for a block the contract sees.
- The owner can replace the observer set and is therefore part of the trust boundary.
- Shared hosting, DNS, RPC providers, or key custody can turn nominally separate observers into
  one failure domain.
- A frozen chain cannot advance its own time or execute a down-marking transaction. Safety is
  enforced when block production resumes.
