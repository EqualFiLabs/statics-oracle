# Statics Oracle

Statics Oracle is the external-asset USD pricing layer for fixed-component Statics
Baskets on Robinhood Chain mainnet (chain ID `4663`). It is a non-upgradeable,
owner-managed registry that binds one exact token contract to one exact Chainlink Data
Feed proxy and returns prices and Basket NAV in 18-decimal USD precision.

The contract is not deployed by this repository. Entries marked `ENABLED` in the
checked-in manifest are the reviewed target configuration, not evidence of live state.

## Security model

The primary failures this project is designed to prevent are:

- selecting a feed by a mutable token symbol or name;
- treating a related crypto wrapper as the approved wrapper;
- accepting a stale, malformed, incomplete, or non-positive feed round;
- consuming L2 prices while the sequencer is down or inside its recovery grace period;
- using a paused Robinhood Stock Token oracle;
- silently changing an enabled asset's feed or policy; and
- producing a partial Basket NAV when any component is invalid.

Every binding is keyed by the token contract address. Registration checks token and feed
bytecode, token decimals, feed decimals, and the hash of the feed description. Stock and
ETF entries must also support `oraclePaused()`. These checks establish exact identity at
registration time; they do not make an external directory or ticker authoritative at
runtime.

The owner remains a trusted security boundary. It can configure the sequencer guard,
register candidates, change disabled bindings, and transition asset states. Ownership uses
OpenZeppelin's two-step transfer flow so a new owner must explicitly accept the role.
Renunciation is intentionally disabled so feed replacement and emergency lifecycle recovery
cannot be permanently abandoned. Operators must independently review the manifest and
destination owner before signing.

## Pricing and lifecycle

`priceUsd(token)` returns the approved token's Chainlink answer normalized to `1e18`.
`valueUsd(token, amount)` computes:

```text
value1e18 = floor(amount * price1e18 / 10**tokenDecimals)
```

`basketNav(assets, amounts)` rejects empty, mismatched, duplicate, or greater-than-16
component arrays, checks the sequencer once, and returns:

```text
nav1e18 = sum(valueUsd(asset[i], amount[i]))
```

All components must be enabled and valid. There is no partial NAV and no fallback price.
`peekPrice` is the diagnostic, non-reverting surface; strict pricing functions map every
non-valid result to a custom error. See [oracle status semantics](docs/ORACLE_STATUS.md).

Assets move through an explicit state machine:

```text
UNSET -> CANDIDATE -> ENABLED -> DISABLED -> CANDIDATE -> ENABLED
           |                         ^
           +--------> DISABLED ------+
```

A candidate is registered for review but cannot price production Baskets. Enabling checks
the stored identity and a currently valid price. An enabled binding cannot be edited; it
must first be disabled. Each successful administrative mutation increments
`registryVersion` exactly once and emits versioned evidence.

## Robinhood Stock Token semantics

Chainlink's Robinhood tokenized-equity feeds already incorporate Robinhood's
`uiMultiplier()` for dividends, splits, and related corporate actions. Statics consumes the
Chainlink answer directly and **must not multiply by `uiMultiplier()` again**.
`uiMultiplier()` is diagnostic metadata only. The independent `oraclePaused()` check is
mandatory for Stock and ETF entries and causes protected pricing to fail closed.

## Sequencer safety

Strict pricing is unavailable unless a configured onchain uptime feed reports the
Robinhood sequencer up and its recovery grace period has elapsed. Missing, malformed, down,
or recently recovered sequencer state fails closed.

The issue and [public Robinhood documentation](https://docs.robinhood.com/chain/connecting/)
currently identify a websocket sequencer data feed, not a canonical onchain
Chainlink-compatible uptime-feed proxy. The checked-in manifest therefore records the
sequencer as unverified, and the configuration script refuses to make any registry
mutation. Production configuration remains blocked until the exact onchain contract and
grace period are independently sourced and reviewed.

## V1 scope

V1 covers exact Robinhood Stock Token, ETF, approved crypto-wrapper, and stable-token
bindings; Chainlink Data Feed reads; per-asset freshness; Stock Token pause handling;
sequencer gating; and fixed-component Basket NAV.

V1 intentionally does **not** implement:

- STATICS token TWAP pricing;
- Basket Token TWAP pricing;
- DEX spot or fallback pricing;
- Chainlink Data Streams;
- Morpho risk policy, LLTV, or liquidation policy;
- dynamic Basket rebalancing; or
- automatic oracle discovery or source-driven configuration changes.

## Sources of truth

- [Requirements](specs/requirements.md)
- [Design](specs/design.md)
- [Implementation plan](specs/tasks.md)
- [Reviewed configuration manifest](config/robinhood-mainnet.assets.json)
- [Oracle whitelist issue](https://github.com/EqualFiLabs/statics-oracle/issues/1)

The specifications define intended behavior, the manifest defines reviewed target
configuration, and an eventual deployed contract will be the runtime source of truth.
External directories are verification inputs only.

## Development and validation

The project uses Foundry with pinned `forge-std` and OpenZeppelin Contracts dependencies.
Deterministic pull-request checks do not require an RPC:

```bash
node --check scripts/generate-whitelist.mjs
node --check scripts/verify-whitelist.mjs
forge fmt --check
forge build
forge test
```

Live validation is separate. Set `ROBINHOOD_MAINNET` to an authorized private,
archive-capable RPC without committing or printing it:

```bash
node scripts/verify-whitelist.mjs
forge test --match-path 'test/fork/*.t.sol'
```

The verifier checks the issue seed, Robinhood and Chainlink directories, exact deployed
contracts, decimals, descriptions, round validity, freshness, and Stock Token pause state.
Identity or live-contract discrepancies are hard failures; review-only source metadata
changes and unresolved candidate gates are warnings. It never rewrites the manifest.

To reproduce the checked-in manifest byte-for-byte, use its `verifiedAtBlock` and
`generatedAt` values:

```bash
node scripts/generate-whitelist.mjs \
  --block <verified-at-block> \
  --generated-at <generated-at>
```

See [adding assets](docs/ADDING_ASSETS.md) and
[replacing feeds](docs/REPLACING_FEEDS.md) before proposing a configuration change.

## Deployment boundary

`DeployStaticsOracle.s.sol` accepts an explicit `INITIAL_OWNER` and refuses any chain other
than Robinhood mainnet. `ConfigureStaticsOracle.s.sol` accepts `STATICS_ORACLE`, consumes
the checked-in manifest, rejects out-of-range numeric fields, and verifies the resulting
sequencer, exact feed binding, feed-description hash, asset kind, decimals, freshness,
pause policy, lifecycle state, and registry version. The configuration script is intended
for a fresh oracle; the broadcasting account must be its owner.

Simulate both scripts and inspect every transaction before adding `--broadcast`. A script
simulation, fork test, or passing CI run is not deployment evidence. This repository's
workflow does not automatically deploy, enable assets, replace feeds, or react to directory
drift.
