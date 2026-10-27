# Execution deployment tooling

The scripts validate chain ID, exact verifier runtime, initial owner and immutable
bundle limit. Configuration validates the whole initial batch before writes,
checks the deployed oracle bindings and fresh registry, sets the existing
sequencer feed, authorizes reviewed application contracts, and registers candidates.
Only rows explicitly marked ENABLED are enabled. Reconfiguration of an existing
registry requires an explicit migration rather than rerunning initialization.

Candidate manifests intentionally contain null unratified values. They cannot
trigger deployment or configuration. Supply a reviewed, qualified manifest before
using the run entry points. Test values do not authorize a live deployment.

The record generator accepts a successful creation receipt and a later pinned
state block, verifies the configured state, and records the creation transaction,
bytecode hashes, owner, immutable bindings, sequencer, known consumers, markets and
registry version. It refuses to overwrite an existing record. Configuration may
span multiple transactions: retain every receipt and verify final state before
handing over the record. Reviewed consumers are not exhaustive enumeration; review
authorization event history separately.

No deployment transaction or production deployment record has been created by
this implementation. Local script tests exercise guards and initial configuration.
