# Reviewed execution stream manifests

Mainnet and testnet configurations are separate. A manifest records exact market
and stream IDs, schema, precision, lifecycle, network-bound verifier runtime,
sequencer binding and review provenance. Market labels use keccak256 of the UTF-8
label for their initial market IDs; the explicit bytes32 binding is authoritative.

Null delay, window or bundle bound means unratified, not zero or a deployment
default. Such rows may remain candidates but cannot be enabled or deployed by the
configuration tooling. Onchain parameters must be positive and precision 0–18.
Reviewed source metadata alone does not prove report authentication on Robinhood.
Discovery drift produces a review report and never rewrites configuration.
