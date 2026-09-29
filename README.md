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
- Robinhood sequencer safety through a threshold-attested observed-availability feed; and
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

Robinhood does not currently publish a canonical onchain uptime-feed proxy. This repository
therefore includes a self-managed, Chainlink-interface-compatible observed-availability feed.
It is not a Chainlink feed and does not prove universal transaction inclusion. A strict
majority of independent observers must agree on fresh Robinhood sequencer-feed progress and a
recent block seen through an independent RPC view. If renewals stop, its 95-second healthy lease
reports expired as soon as chain time reaches the deadline, without requiring a marking
transaction. Production use still requires deployment,
independent operators, key custody, monitoring, and an explicitly reviewed recovery grace
period. See [Sequencer signal operations](docs/SEQUENCER_SIGNAL.md).
Asset-specific feed heartbeats and `maxAge` policies must likewise be sourced and reviewed
before an asset is enabled; placeholder safety parameters are not acceptable.

## Sequencer signal development

The `observer/` package contains two separately deployable processes: an observer that signs
only after checking the direct sequencer feed against an independent RPC, and a permissionless
coordinator that gathers quorum and relays the observation. Three independent observers with a
two-signature threshold are the minimum supported set.

```bash
cd observer
npm ci
npm test
```

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

Verify the checked-in manifest without modifying it:

```bash
node scripts/verify-whitelist.mjs
```

Identity, missing-contract, decimal, description-hash, and invalid-round findings are hard
failures. Non-identity directory metadata changes and unresolved candidate-risk gates are
reported as review warnings. Source drift is never applied automatically. Pass `--block`
to reproduce a historical verification against an archive-capable RPC.

Block-pinned fork tests read the checked-in manifest and skip when the RPC variable is absent:

```bash
forge test --match-path 'test/fork/*.t.sol'
```
