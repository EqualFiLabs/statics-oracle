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

## Progress

- 1.1 Consumer interface defined; economic types excluded.
