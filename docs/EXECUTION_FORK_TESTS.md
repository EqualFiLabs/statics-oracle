# Execution integration evidence

The committed chain bindings pin independently sourced mainnet/testnet verifier
addresses, runtime hashes, identity and archive blocks. Run the execution fork
suite with the configured private RPC variables already loaded. Missing RPCs
skip these tests; a skip is not a passing integration result.

Real report validation requires a licensed signed capture. Store it in the ignored
fixture location under config and set EXECUTION_REPORT_FIXTURE to that location.
The example defines the required fields. Preserve exact fullReports, every expected
verified body, the selected body, real inclusion-block timestamp, and matching
provisional execution configuration. Never fabricate signatures or substitute a
mock verifier to satisfy this gate. The test checks direct subscription bulk
verification and adapter output against the real verifier at the recorded block.

No signed capture has been committed. Report fixtures are licensed data, and
subscription credentials never belong in fixture files. Production timing and
bundle-size qualification remain separate from this integration harness.
