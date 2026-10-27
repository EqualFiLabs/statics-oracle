# Execution oracle delivery

The synthetic execution adapter is separate from the address-keyed NAV oracle.
The approved implementation scope covers tasks 1–17 of the execution-oracle
specification, followed by a BucketPerps integration handoff. Each task is a
separate dependent PR; numbered subtasks are separate commits.

Execution authenticates the whole bounded bundle and validates every V3 body.
Unordered bundles are accepted. Exactly one inclusive signed window must contain
the transaction timestamp minus the configured delay. Matching duplicates fail;
nonmatching duplicates count toward the bound. No global watermark or price cache
exists. Independent signed bundles have the same acceptance as service output.

Production timing, the immutable bundle bound, downstream economic qualification,
and BucketPerps integration remain separate release prerequisites. Development
parameters and local tests do not establish production readiness.

## Checkpoint A

Configuration lifecycle and consumer/sequencer administration pass focused local
Foundry tests. Invalid transitions and unauthorized mutations fail, and failed
configuration changes preserve the registry version. Existing NAV sequencer tests
also pass. Verification remains unavailable until the authenticated selection
path is complete; this checkpoint is not an execution or deployment claim.

## Checkpoint B

The complete authenticated path passes local mocked-verifier execution tests:
unique inclusive selection, unordered input, nonmatching duplicates, matching
duplicate rejection, metadata and normalized consensus price. Every body is
validated before success, and no price or observation watermark is stored.
These tests do not establish real Chainlink subscription or deployment behavior.

## Checkpoint C

Local unit tests and generated properties pass, including a 256-run registry
invariant campaign with 16,384 handler calls and zero reverts. A pinned private-RPC
fork run passes four checks: canonical verifier identity/runtime on both networks,
forged-payload rejection, mainnet archive binding and deployed sequencer
health/grace/lease-expiry behavior. Mainnet block: 99,517,116; testnet: 143,784,728.

Real signed-report authentication is explicitly pending a licensed capture and
subscription credentials. Its test exists and skips when the fixture is absent;
that skip does not satisfy the real-report gate. No deployment was broadcast.

## Progress

- 1.1–1.3 Consumer ABI, bulk verifier ABI and V3 types defined.
- 1.4 Reuse OpenZeppelin Ownable2Step, IAggregatorV3 and OracleMath.
  Supported stream precision is 0–18; higher precision fails instead of truncating.
  Existing NAV and sequencer contracts remain unchanged.

## Checkpoint D and integration boundary

The oracle, deployment tooling and dedicated signed-report relay are implemented.
Full local validation passes: 168 Foundry tests, 39 observer-service tests,
14 relay tests and five manifest/deployment-tooling tests. The default Foundry
run skips twelve network/fixture-dependent tests. The separate pinned Robinhood
execution run passes four checks and skips the signed-report test without its
private capture. These are separate evidence sets.

| Checkpoint D requirement | Evidence and status |
| --- | --- |
| Fetch current signed reports | Transport implemented; live subscription check pending credentials |
| Keep secrets server-side | Credential isolation and HTTP authorization tests pass |
| Preserve report bytes to the client | SDK transport through HTTP fixture tests pass byte for byte |
| Prevent relay price authority | Consumer authenticates bodies and selects by transaction time; no relay price input |
| Authenticate relay output independently | Mocked path and real forged-payload rejection pass; authentic capture still pending |
| Avoid generic redistribution | Protected market-label-only endpoint; arbitrary feeds/history requests rejected |

Checkpoint D remains conditional until current licensed reports traverse the relay
and authenticate against the real subscription verifier. Unsigned ABI fixtures in
relay tests establish transport behavior only. Candidate manifests cannot deploy
until production parameters and stream authentication are qualified. No deployment
or signing operation was performed.

Implementation commits cover numbered tasks 1–16. The task 17 handoff documents
the remaining live checkpoint and the exact task 18 consumer contract. The actual
BucketPerps integration and tasks 18–26 remain open. See
[the integration handoff](BUCKETPERPS_EXECUTION_HANDOFF.md).
