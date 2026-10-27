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

The initial BTC/USD and ETH/USD rows are Crypto Advanced V3 consensus reference
streams with 18 decimals. Mainnet source catalog rows are live; testnet rows are
explicitly testing. These are candidates, not enabled markets or launch approval.
The mainnet catalog's sourceChain denotes the DON source environment rather than
the target execution chain. Robinhood support is independently bound to its
canonical verifier; real signed authentication remains a separate pending gate.

The recorded verifier identity is VerifierProxy 2.0.0. The reviewed runtime and
archive blocks are in the chain bindings. Recheck runtime, stream status,
deprecation, precision and subscription compatibility before enabling any row.
No stream replacement or timing decision is automatic.
