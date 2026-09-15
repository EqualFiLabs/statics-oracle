# Statics Oracle

Statics Oracle is the external-asset USD pricing layer for Statics Baskets on Robinhood
Chain mainnet (chain ID `4663`).

The system binds an exact Robinhood Chain token contract to an exact Chainlink Data Feed
proxy. Token symbols and names are display metadata; they never select an oracle. Valid
feed answers are normalized to 18-decimal USD values for fixed-amount Basket NAV
calculation.

## V1 scope

V1 covers:

- Robinhood Stock Tokens and ETFs;
- explicitly approved crypto-token wrappers;
- Chainlink Data Feed proxy reads;
- per-asset freshness and feed-integrity policy;
- Robinhood Stock Token oracle-pause handling;
- Robinhood sequencer safety once its canonical uptime feed is verified; and
- fixed-component Statics Basket NAV.

V1 intentionally excludes STATICS pricing, Basket Token TWAPs, DEX fallback pricing,
Chainlink Data Streams, dynamic Basket rebalancing, Morpho LLTV policy, liquidation logic,
and automatic oracle discovery.

## Source of truth

- [Requirements](specs/requirements.md)
- [Design](specs/design.md)
- [Implementation plan](specs/tasks.md)
- [Oracle whitelist issue](https://github.com/EqualFiLabs/statics-oracle/issues/1)

The checked-in specifications define intended behavior. The generated whitelist manifest
will provide reproducible configuration evidence, while the deployed contract will remain
the runtime source of truth.

## Development

The project uses Foundry with pinned `forge-std` and OpenZeppelin Contracts dependencies.

```bash
forge fmt --check
forge build
forge test
```

Live Robinhood validation is deliberately separate from deterministic local and pull-request
checks. Never commit RPC URLs, credentials, or signer material.

## Production release gates

Production configuration must use an independently verified canonical Robinhood Chain
sequencer uptime-feed proxy and an explicitly reviewed recovery grace period. Neither value
is assumed by the contracts or this repository while the canonical feed remains unresolved.
Asset-specific feed heartbeats and `maxAge` policies must likewise be sourced and reviewed
before an asset is enabled; placeholder safety parameters are not acceptable.

## Whitelist generation

The checked-in Robinhood Mainnet manifest is generated from the exact issue-approved
token/feed matrix, the canonical Robinhood and Chainlink directories, and block-pinned
contract reads. Its lifecycle values are desired configuration, not evidence of deployment.

```bash
export ROBINHOOD_MAINNET="<private-rpc-url>"
node scripts/generate-whitelist.mjs --block <verified-block>
```

For byte-for-byte reproduction, also pass the checked-in `generatedAt` value through
`--generated-at`. The generator fails on missing source rows, identity disagreement,
missing bytecode, metadata mismatch, invalid rounds, stale answers, or paused stock oracles.
