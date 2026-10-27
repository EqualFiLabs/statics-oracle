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

## Progress

- 1.1–1.3 Consumer ABI, bulk verifier ABI and V3 types defined.
- 1.4 Reuse OpenZeppelin Ownable2Step, IAggregatorV3 and OracleMath.
  Supported stream precision is 0–18; higher precision fails instead of truncating.
  Existing NAV and sequencer contracts remain unchanged.
