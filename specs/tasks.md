# Implementation Plan: Robinhood Chain Oracle Whitelist

## Overview

Build the `statics-oracle` repository as a greenfield Foundry project providing deterministic external-asset USD pricing for Statics on Robinhood Chain.

Implementation proceeds bottom-up:

1. repository/bootstrap,
2. interfaces and shared types,
3. math and configuration primitives,
4. oracle registry and lifecycle,
5. price validation,
6. Basket NAV,
7. machine-readable whitelist tooling,
8. unit/fuzz/fork testing,
9. deployment and operational documentation.

The implementation SHALL remain limited to Chainlink-based external asset pricing. STATICS TWAP pricing, Basket Token TWAPs, DEX fallback pricing, Chainlink Data Streams, Morpho risk parameters, and liquidation policy remain outside this spec.

---

# Tasks

- [x] 1. Bootstrap the `statics-oracle` Foundry project
  - [x] 1.1 Initialize Foundry project structure
    - **New files:**
      - `foundry.toml`
      - `remappings.txt`
      - `src/`
      - `test/`
      - `script/`
      - `scripts/`
      - `config/`
    - Configure Solidity version, optimizer settings, fuzz runs, and Robinhood Chain RPC environment variables.
    - Configure Robinhood Chain ID `4663` as the expected production network.
    - Do not hardcode private RPC URLs or secrets.
    - _Requirements: 1.1, 1.4, 1.5_

  - [x] 1.2 Add minimal dependencies
    - Add `forge-std`.
    - Add OpenZeppelin Contracts for `Ownable2Step`, `Math.mulDiv`, and standard utilities where appropriate.
    - Avoid adding unnecessary oracle frameworks or upgradeability libraries.
    - _Requirements: 14.1-14.7_

  - [x] 1.3 Create repository README skeleton
    - **New file:** `README.md`
    - Document:
      - project purpose,
      - Robinhood Chain scope,
      - Chainlink as primary oracle source,
      - external-asset-only V1 scope,
      - explicit non-goals.
    - _Requirements: 1.1-1.3, 14.1-14.7_

- [x] 2. Define interfaces, enums, and shared data structures
  - [x] 2.1 Create Chainlink V3 interface
    - **New file:** `src/interfaces/IAggregatorV3.sol`
    - Include:
      - `decimals()`
      - `description()`
      - `latestRoundData()`
    - Keep the interface minimal.
    - _Requirements: 3.2, 3.7, 3.9, 6.1-6.9_

  - [x] 2.2 Create Robinhood Stock Token interface
    - **New file:** `src/interfaces/IRobinhoodStockToken.sol`
    - Include:
      - `oraclePaused()`
      - `decimals()`
    - MAY include `uiMultiplier()` only for testing/diagnostics.
    - Ensure production pricing logic does not depend on `uiMultiplier()`.
    - _Requirements: 4.1-4.7, 13.5, 13.6_

  - [x] 2.3 Create Statics oracle consumer interface
    - **New file:** `src/interfaces/IStaticsOracle.sol`
    - Define:
      - `AssetKind`
      - `AssetStatus`
      - `OracleStatus`
      - `AssetOracleConfig`
      - `PriceData`
      - consumer-facing functions:
        - `priceUsd(address)`
        - `valueUsd(address,uint256)`
        - `basketNav(address[],uint256[])`
        - `peekPrice(address)`
        - `assetConfig(address)`
        - `registryVersion()`
    - _Requirements: 8.1-8.7, 9.1-9.8, 10.1-10.8, 12.1-12.10_

  - [x] 2.4 Define administrative configuration input types
    - Add a configuration input struct suitable for registration and controlled updates.
    - Include:
      - feed,
      - expected feed description hash,
      - max age,
      - expected token decimals,
      - expected feed decimals,
      - asset kind,
      - pause-check requirement.
    - Do not use symbol/name as a security-critical input.
    - _Requirements: 2.1-2.7, 3.8, 3.9, 11.2_

- [x] 3. Implement normalization and valuation math
  - [x] 3.1 Create `OracleMath`
    - **New file:** `src/libraries/OracleMath.sol`
    - Implement:
      - feed-answer normalization to `1e18`,
      - raw token amount to `1e18` USD valuation.
    - Use full-precision multiplication where required.
    - _Requirements: 8.1, 8.2, 9.2, 9.4, 9.5_

  - [x] 3.2 Enforce supported decimal bounds
    - Reject unsupported token/feed decimal configurations rather than silently truncating or overflowing.
    - Initial implementation SHOULD support decimal counts up to `18`.
    - Add explicit custom errors for unsupported decimal values.
    - _Requirements: 3.8, 3.9, 8.2_

  - [x] 3.3 Add OracleMath unit tests
    - **New file:** `test/unit/OracleMath.t.sol`
    - Cover:
      - 6-decimal tokens,
      - 8-decimal tokens,
      - 18-decimal tokens,
      - 8-decimal feeds,
      - 18-decimal feeds,
      - zero amount,
      - large amounts,
      - rounding behavior.
    - _Requirements: 13.3, 13.4_

- [x] 4. Implement the authoritative oracle registry and lifecycle
  - [x] 4.1 Create `StaticsOracle`
    - **New file:** `src/StaticsOracle.sol`
    - Inherit from:
      - `Ownable2Step`
      - `IStaticsOracle`
    - Store configuration keyed strictly by token address.
    - Do not implement symbol-based lookup.
    - _Requirements: 2.1-2.7, 10.1-10.8_

  - [x] 4.2 Implement asset registration
    - Add:
      ```solidity
      registerAsset(address token, AssetOracleConfigInput calldata config)
      ```
    - Validate:
      - nonzero token,
      - nonzero feed,
      - token code exists,
      - feed code exists,
      - token decimals match,
      - feed decimals match,
      - feed description hash matches,
      - `maxAge > 0`,
      - decimal bounds,
      - Stock/ETF pause requirements.
    - New assets SHALL enter `CANDIDATE`.
    - _Requirements: 3.1-3.9, 10.1-10.3_

  - [x] 4.3 Implement lifecycle transitions
    - Add:
      - `enableAsset(address)`
      - `disableAsset(address)`
      - controlled configuration update function.
    - Enforce lifecycle:
      ```text
      UNSET -> CANDIDATE -> ENABLED
                          -> DISABLED
      ENABLED -> DISABLED -> CANDIDATE
      ```
    - Do not allow material configuration mutation while `ENABLED`.
    - _Requirements: 10.1-10.6_

  - [x] 4.4 Implement registry versioning
    - Add:
      ```solidity
      uint64 public registryVersion;
      ```
    - Increment exactly once per successful configuration mutation.
    - Emit complete audit events.
    - Include config hash for registrations and updates.
    - _Requirements: 10.7, 11.1-11.7_

  - [x] 4.5 Implement deterministic custom errors
    - Add custom errors covering:
      - unsupported asset,
      - wrong lifecycle state,
      - zero addresses,
      - invalid decimals,
      - feed description mismatch,
      - invalid max age,
      - invalid transitions,
      - mutation while enabled.
    - Avoid revert strings.
    - _Requirements: 12.1-12.10_

## Checkpoint A

- [x] 5. Checkpoint: registry and primitive correctness
  - Run:
    ```text
    forge fmt --check
    forge build
    forge test test/unit/OracleMath.t.sol
    ```
  - Confirm:
    - address-based registry compiles,
    - lifecycle cannot silently replace enabled bindings,
    - math normalizes correctly,
    - no STATICS or Basket TWAP functionality has entered scope.
  - _Requirements: 2, 8, 10, 14_

- [x] 6. Implement sequencer safety
  - [x] 6.1 Add sequencer configuration storage
    - Store:
      - sequencer feed address,
      - recovery grace period.
    - Add:
      ```solidity
      setSequencerConfig(address feed, uint32 gracePeriod)
      ```
    - Validate code exists and feed can be called.
    - _Requirements: 7.1, 7.4, 7.5_

  - [x] 6.2 Implement internal sequencer evaluator
    - Implement explicit states:
      - not configured,
      - down,
      - recovery grace,
      - healthy.
    - Treat standard Chainlink uptime answer:
      - `0 = up`
      - nonzero = unavailable.
    - _Requirements: 7.2, 7.3, 12.7, 12.8_

  - [x] 6.3 Add release gate for canonical sequencer feed
    - Do NOT add a guessed Robinhood Chain uptime-feed address.
    - Keep manifest sequencer state unverified until an authoritative source is found.
    - Mainnet production enablement SHALL require an independently verified address.
    - _Requirements: 7.1, 7.4, 7.5_

- [x] 7. Implement oracle price evaluation
  - [x] 7.1 Implement `_evaluatePrice`
    - Create an internal non-reverting evaluation path returning `PriceData`.
    - Evaluate in deterministic order:
      1. lifecycle,
      2. sequencer,
      3. stock pause state,
      4. feed call,
      5. positive answer,
      6. round completeness,
      7. timestamp validity,
      8. freshness,
      9. normalization.
    - _Requirements: 4.6, 6.1-6.9, 7.1-7.5, 12.1-12.10_

  - [x] 7.2 Implement stock and ETF pause handling
    - For Stock/ETF assets:
      - require pause checking in V1 configuration,
      - call `oraclePaused()`,
      - return paused status when true,
      - return explicit failure status if the pause call itself fails.
    - Do not use `uiMultiplier()` in valuation.
    - _Requirements: 4.1-4.7, 12.6_

  - [x] 7.3 Implement Chainlink round validation
    - Reject:
      - `answer <= 0`,
      - `updatedAt == 0`,
      - `answeredInRound < roundId`,
      - `updatedAt > block.timestamp`,
      - `block.timestamp - updatedAt > maxAge`.
    - Preserve round metadata in `PriceData`.
    - _Requirements: 6.1-6.9_

  - [x] 7.4 Implement feed normalization
    - Normalize validated answers using configured feed decimals.
    - Return `price1e18`.
    - _Requirements: 8.1-8.4_

- [x] 8. Implement strict consumer-facing pricing
  - [x] 8.1 Implement `peekPrice`
    - Return diagnostic `PriceData` without forcing callers to parse reverts.
    - Include:
      - normalized price where available,
      - timestamp,
      - round ID,
      - explicit `OracleStatus`.
    - _Requirements: 8.3, 8.4, 12.1-12.10_

  - [x] 8.2 Implement `priceUsd`
    - Strictly require `OracleStatus.VALID`.
    - Map all other statuses into deterministic custom errors.
    - Do not return stale or paused prices as successful results.
    - _Requirements: 8.1-8.7, 12.1-12.10_

  - [x] 8.3 Implement `valueUsd`
    - Price the exact token.
    - Apply raw token amount and token decimals.
    - Use `OracleMath`.
    - _Requirements: 8.1-8.7, 9.2, 9.4_

  - [x] 8.4 Prohibit fallback pricing
    - Verify no path exists from invalid Chainlink price to:
      - DEX spot,
      - token symbol,
      - another wrapper's oracle,
      - another provider.
    - _Requirements: 5.1-5.7, 8.6, 8.7, 14.4_

- [x] 9. Implement Basket NAV aggregation
  - [x] 9.1 Implement `basketNav`
    - Add:
      ```solidity
      basketNav(
          address[] calldata assets,
          uint256[] calldata amounts
      )
      ```
    - Require:
      - equal lengths,
      - non-empty arrays,
      - <= 16 assets.
    - _Requirements: 9.1-9.7_

  - [x] 9.2 Reject duplicate Basket assets
    - Reject duplicate token addresses in a single NAV calculation.
    - Preserve parity with Statics Basket creation invariants.
    - _Requirements: 9.1, 9.6_

  - [x] 9.3 Optimize sequencer validation
    - Check sequencer once per Basket NAV call.
    - Do not perform one sequencer feed call per underlying.
    - _Requirements: 7.2, 7.3, 9.1-9.7_

  - [x] 9.4 Aggregate fixed underlying amounts
    - For each component:
      ```text
      componentUsd =
          amount[i] * price1e18[i] / 10^tokenDecimals[i]
      ```
    - Sum all contributions.
    - Revert if any component is not strictly valid.
    - _Requirements: 9.1-9.7_

## Checkpoint B

- [x] 10. Checkpoint: complete onchain oracle behavior
  - Run all deterministic unit tests.
  - Confirm:
    - lifecycle gating works,
    - stock pause works,
    - staleness works,
    - sequencer states work,
    - wrappers remain isolated,
    - NAV is additive,
    - invalid component invalidates strict NAV.
  - _Requirements: 4-10, 12-13_

- [x] 11. Create the machine-readable Robinhood whitelist manifest
  - [x] 11.1 Define manifest schema
    - **New file:** `config/robinhood-mainnet.assets.json`
    - Include:
      - schema version,
      - chain ID,
      - quote currency,
      - generation timestamp,
      - verified block,
      - canonical source URLs,
      - sequencer configuration,
      - asset rows.
    - _Requirements: 11.1-11.7_

  - [x] 11.2 Seed V1 Stock/ETF matrix
    - Add the approved target rows from the requirements:
      - AAPL
      - NVDA
      - MSFT
      - GOOGL
      - AMZN
      - META
      - TSLA
      - AMD
      - PLTR
      - COIN
      - MSTR
      - CRCL
      - ORCL
      - SPY
      - QQQ
    - Preserve exact token/feed bindings from the reviewed whitelist.
    - _Requirements: 2.7, 11.1-11.7_

  - [x] 11.3 Seed crypto matrix
    - Add:
      - WETH
      - USDG
      - LINK
      - WBTC
      - cbBTC
      - USDC
      - USDT
      - wstETH.
    - Keep only WETH and USDG as initial enabled targets unless candidate provenance/risk review is separately completed.
    - Keep the remaining crypto entries as `CANDIDATE`.
    - _Requirements: 5.1-5.7, 10.1-10.4, 11.1-11.7_

  - [x] 11.4 Record provenance metadata
    - Every asset entry SHALL record:
      - token address,
      - feed address,
      - decimals,
      - feed description,
      - source-match status,
      - verification block/time,
      - lifecycle status.
    - _Requirements: 11.2-11.7_

- [x] 12. Build whitelist generation tooling
  - [x] 12.1 Implement source fetcher
    - **New file:** `scripts/generate-whitelist.mjs`
    - Fetch:
      - Robinhood `/rhj/assets`,
      - Chainlink Robinhood feed directory.
    - Fail on unavailable or malformed canonical sources.
    - _Requirements: 3.1-3.6, 11.3-11.7_

  - [x] 12.2 Implement exact Robinhood asset matching
    - Resolve requested Stock/ETF rows against the Robinhood asset registry using exact canonical identity.
    - Do not match solely on ticker where ambiguity exists.
    - Reject source disagreement.
    - _Requirements: 2.3-2.7, 3.1, 3.3, 3.5, 3.6_

  - [x] 12.3 Implement exact Chainlink feed matching
    - Resolve expected asset/feed pairs against Chainlink's Robinhood feed directory.
    - Record:
      - proxy,
      - feed decimals,
      - description,
      - heartbeat metadata where available.
    - Fail if expected feed cannot be resolved.
    - _Requirements: 3.2, 3.4, 3.6, 3.9_

  - [x] 12.4 Implement Robinhood RPC verification
    - Verify:
      - token bytecode,
      - feed bytecode,
      - token decimals,
      - feed decimals,
      - feed description,
      - positive current feed answer.
    - Record verification block.
    - _Requirements: 3.7-3.9, 6.1-6.4, 11.4-11.6_

  - [x] 12.5 Generate deterministic manifest output
    - Sort assets deterministically.
    - Produce stable JSON formatting.
    - Fail rather than silently omitting a requested asset.
    - _Requirements: 11.1-11.7_

- [x] 13. Build whitelist verification tooling
  - [x] 13.1 Implement live manifest verifier
    - **New file:** `scripts/verify-whitelist.mjs`
    - Compare checked-in manifest against:
      - Robinhood registry,
      - Chainlink directory,
      - Robinhood Chain contracts.
    - _Requirements: 3.1-3.9, 11.6, 11.7_

  - [x] 13.2 Detect canonical source drift
    - Report:
      - changed token address,
      - changed feed proxy,
      - changed decimals,
      - changed description,
      - missing source asset,
      - missing feed.
    - Do not automatically rewrite production configuration.
    - _Requirements: 10.5, 10.6, 11.7_

  - [x] 13.3 Distinguish warnings from hard failures
    - Hard fail:
      - identity mismatch,
      - missing canonical contract,
      - feed mismatch,
      - invalid decimals,
      - invalid price.
    - Review warning:
      - candidate asset liquidity/provenance review still pending,
      - source metadata changed without affecting approved identity.
    - _Requirements: 3.6, 5.7, 10.2, 11.7_

## Checkpoint C

- [x] 14. Checkpoint: reproducible whitelist
  - Regenerate the manifest.
  - Re-run live verification.
  - Compare generated output to checked-in output.
  - Confirm no ticker-based resolution can silently change bindings.
  - Confirm candidate crypto assets remain unavailable for strict production pricing.
  - _Requirements: 2, 3, 5, 10, 11_

- [x] 15. Build full configuration and lifecycle unit tests
  - [x] 15.1 Create configuration test suite
    - **New file:** `test/unit/StaticsOracle.Config.t.sol`
    - Test:
      - valid registration,
      - duplicate registration,
      - zero addresses,
      - no-code token,
      - no-code feed,
      - wrong token decimals,
      - wrong feed decimals,
      - wrong feed description,
      - zero `maxAge`,
      - invalid Stock/ETF pause configuration.
    - _Requirements: 3.7-3.9, 10.1-10.6, 13.9_

  - [x] 15.2 Test lifecycle state machine
    - Cover:
      - `UNSET -> CANDIDATE`,
      - `CANDIDATE -> ENABLED`,
      - `ENABLED -> DISABLED`,
      - `DISABLED -> CANDIDATE`,
      - invalid transitions,
      - configuration mutation while enabled.
    - _Requirements: 10.1-10.6_

  - [x] 15.3 Test registry versioning
    - Assert every successful admin mutation increments version exactly once.
    - Assert failed changes do not increment.
    - Assert view/price calls do not increment.
    - _Requirements: 10.7, 11.1-11.7_

- [x] 16. Build price validation tests
  - [x] 16.1 Create price test suite
    - **New file:** `test/unit/StaticsOracle.Price.t.sol`
    - Test:
      - valid answer,
      - zero answer,
      - negative answer,
      - zero timestamp,
      - future timestamp,
      - stale result,
      - incomplete round,
      - failed feed call.
    - _Requirements: 6.1-6.9, 12.2-12.5, 13.7_

  - [x] 16.2 Test lifecycle-aware pricing
    - Verify:
      - unregistered token fails,
      - candidate fails,
      - disabled fails,
      - enabled succeeds.
    - _Requirements: 8.5, 10.1-10.4, 12.1_

  - [x] 16.3 Test diagnostic versus strict behavior
    - `peekPrice()` returns explicit status.
    - `priceUsd()` reverts on any non-valid status.
    - _Requirements: 8.3-8.6, 12.1-12.10_

- [x] 17. Build stock-specific regression tests
  - [x] 17.1 Create stock test suite
    - **New file:** `test/unit/StaticsOracle.Stock.t.sol`
    - Test:
      - normal Stock Token price,
      - paused token,
      - failed `oraclePaused()` call.
    - _Requirements: 4.1-4.7, 13.7_

  - [x] 17.2 Prove `uiMultiplier()` is not double-applied
    - Build a mock whose multiplier changes independently.
    - Verify Statics arithmetic depends only on the feed answer.
    - _Requirements: 4.2-4.4, 13.5_

  - [x] 17.3 Test dividend continuity scenario
    - Simulate:
      - underlying reference unchanged,
      - multiplier increases,
      - Chainlink token price increases accordingly.
    - Verify Statics uses the already-adjusted feed price once.
    - _Requirements: 4.2-4.4, 13.6_

  - [x] 17.4 Test split continuity scenario
    - Simulate representative share-price and multiplier changes.
    - Verify Basket token-value calculation remains economically continuous according to Chainlink output.
    - _Requirements: 4.2-4.4, 13.6_

- [x] 18. Build sequencer tests
  - [x] 18.1 Create sequencer test suite
    - **New file:** `test/unit/StaticsOracle.Sequencer.t.sol`
    - Cover:
      - missing config,
      - healthy sequencer,
      - down sequencer,
      - recovery grace period,
      - grace-period expiry,
      - malformed feed behavior.
    - _Requirements: 7.1-7.5, 12.7, 12.8, 13.10_

  - [x] 18.2 Verify strict price gating
    - Prove an otherwise valid price fails while:
      - sequencer is down,
      - grace period is active.
    - _Requirements: 7.2, 7.3, 13.10_

- [ ] 19. Build Basket NAV tests
  - [ ] 19.1 Create NAV test suite
    - **New file:** `test/unit/StaticsOracle.Nav.t.sol`
    - Cover:
      - single asset,
      - two assets,
      - mixed token decimals,
      - mixed feed decimals,
      - zero amount,
      - array length mismatch,
      - empty Basket,
      - duplicate token,
      - 16 assets,
      - >16 assets.
    - _Requirements: 9.1-9.7, 13.11_

  - [ ] 19.2 Test invalid component propagation
    - Prove that one:
      - stale,
      - paused,
      - disabled,
      - unsupported,
      - sequencer-invalid
      component invalidates strict NAV.
    - _Requirements: 9.7, 13.7-13.11_

  - [ ] 19.3 Test representative Statics Basket
    - Example:
      ```text
      0.1 NVDA
      0.3 WETH
      0.08 SPY
      ```
    - Verify expected NAV from fixed underlying quantities.
    - _Requirements: 9.1-9.6_

## Checkpoint D

- [ ] 20. Checkpoint: deterministic safety coverage
  - Run all unit suites.
  - Confirm every explicit `OracleStatus` and strict custom error has coverage.
  - Confirm Stock Token multiplier regression tests exist.
  - Confirm wrapper identity cannot cross-resolve.
  - Confirm invalid oracle conditions cannot produce successful NAV.
  - _Requirements: 12, 13_

- [ ] 21. Add fuzz and property testing
  - [ ] 21.1 Fuzz normalization math
    - **New file:** `test/fuzz/OracleMath.t.sol`
    - Fuzz:
      - amount,
      - price,
      - token decimals,
      - feed decimals.
    - Bound values to supported ranges.
    - _Requirements: 13.3, 13.4_

  - [ ] 21.2 Prove NAV additivity
    - **New file:** `test/fuzz/NavProperties.t.sol`
    - Prove:
      ```text
      basketNav([A,B],[x,y])
      ≈
      valueUsd(A,x) + valueUsd(B,y)
      ```
      subject only to defined rounding.
    - _Requirements: 9.2, 9.3, 13.11_

  - [ ] 21.3 Prove address isolation
    - **New file:** `test/fuzz/AddressIsolation.t.sol`
    - Generate arbitrary lookalike tokens.
    - Prove same ticker/name cannot inherit approved configuration.
    - _Requirements: 2.3-2.6, 13.1_

  - [ ] 21.4 Prove wrapper isolation
    - Test arbitrary economically equivalent wrapper mocks.
    - Prove an approved WBTC-style token does not make an unapproved BTC wrapper priceable.
    - _Requirements: 5.1-5.7, 13.2_

  - [ ] 21.5 Prove registry version monotonicity
    - Fuzz valid sequences of admin actions.
    - Assert exactly one version increment for each successful mutation.
    - _Requirements: 10.7, 11.1-11.7_

- [ ] 22. Add Robinhood Chain fork tests
  - [ ] 22.1 Create live feed fork suite
    - **New file:** `test/fork/RobinhoodFeeds.t.sol`
    - For every enabled target:
      - verify token code,
      - verify feed code,
      - verify decimals,
      - verify description,
      - verify latest positive answer,
      - verify Stock/ETF pause method can be called.
    - _Requirements: 3.7-3.9, 11.4-11.6, 13_

  - [ ] 22.2 Create full whitelist matrix fork suite
    - **New file:** `test/fork/WhitelistMatrix.t.sol`
    - Read or derive expected configuration from the checked-in manifest.
    - Avoid duplicating the whitelist in Solidity constants where practical.
    - Verify candidates as identity-valid even when not enabled.
    - _Requirements: 3.1-3.9, 5.7, 11.1-11.7_

  - [ ] 22.3 Add production sequencer fork test only after canonical address resolution
    - Do not block deterministic local testing on an unverified address.
    - Once resolved:
      - add it to the manifest,
      - verify code,
      - verify Chainlink interface,
      - add fork coverage.
    - _Requirements: 7.1-7.5_

- [ ] 23. Create deployment scripts
  - [ ] 23.1 Create oracle deployment script
    - **New file:** `script/DeployStaticsOracle.s.sol`
    - Deploy non-upgradeable `StaticsOracle`.
    - Set initial owner explicitly.
    - Validate chain ID before production deployment.
    - _Requirements: 1.1, 1.4, 1.5, 10_

  - [ ] 23.2 Create configuration script
    - **New file:** `script/ConfigureStaticsOracle.s.sol`
    - Load or consume reviewed manifest configuration.
    - Register assets as candidates.
    - Configure verified sequencer feed.
    - Enable only approved V1 assets.
    - Leave candidate crypto assets disabled/candidate.
    - _Requirements: 5.7, 7.1, 10.1-10.4, 11_

  - [ ] 23.3 Add deployed-state verifier
    - Compare onchain:
      - feed,
      - decimals,
      - status,
      - max age,
      - pause policy,
      - registry version
      against expected manifest values.
    - _Requirements: 10.5-10.7, 11.6, 11.7_

- [ ] 24. Add CI
  - [ ] 24.1 Add deterministic PR workflow
    - **New file:** `.github/workflows/ci.yml`
    - Run:
      ```text
      forge fmt --check
      forge build
      forge test
      ```
    - Unit and fuzz tests MUST NOT depend on public RPC availability.
    - _Requirements: 13.1-13.11_

  - [ ] 24.2 Add live validation workflow
    - **New file:** `.github/workflows/oracle-validation.yml`
    - Run on:
      - manual dispatch,
      - scheduled cadence,
      - optionally release branches.
    - Execute:
      - live manifest verification,
      - Robinhood fork tests.
    - _Requirements: 3, 11, 13_

  - [ ] 24.3 Prevent automatic source-driven mutations
    - CI may report drift.
    - CI SHALL NOT automatically rewrite the whitelist or submit production feed replacements.
    - _Requirements: 10.5, 10.6, 11.7_

- [ ] 25. Document whitelist and operations
  - [ ] 25.1 Complete `README.md`
    - Explain:
      - threat model,
      - token/feed binding model,
      - Stock Token multiplier semantics,
      - lifecycle states,
      - Basket NAV formula,
      - sequencer safety,
      - candidate versus enabled assets.
    - _Requirements: 2, 4, 5, 7-11_

  - [ ] 25.2 Document asset addition procedure
    - **New file:** `docs/ADDING_ASSETS.md`
    - Procedure:
      1. identify exact token,
      2. verify Robinhood provenance where applicable,
      3. identify exact Chainlink proxy,
      4. verify decimals/description,
      5. assess wrapper provenance,
      6. add as candidate,
      7. run live verification,
      8. review,
      9. explicitly enable.
    - _Requirements: 3.1-3.9, 10.8, 11.7_

  - [ ] 25.3 Document feed replacement procedure
    - **New file:** `docs/REPLACING_FEEDS.md`
    - Require:
      ```text
      ENABLED
      -> DISABLED
      -> update binding
      -> CANDIDATE
      -> verify
      -> ENABLED
      ```
    - Explain why external directory changes do not automatically modify protocol configuration.
    - _Requirements: 10.5-10.8_

  - [ ] 25.4 Document failure semantics
    - **New file:** `docs/ORACLE_STATUS.md`
    - Map every `OracleStatus` to:
      - meaning,
      - strict-function behavior,
      - operator response.
    - _Requirements: 12.1-12.10_

  - [ ] 25.5 Document current V1 scope exclusions
    - Explicitly state that this repository does not yet implement:
      - STATICS TWAP,
      - Basket Token TWAP,
      - DEX fallback,
      - Data Streams,
      - Morpho risk policy.
    - _Requirements: 14.1-14.7_

---

# Suggested PR Stack

The implementation can be cleanly delivered as the following stacked PRs:

```text
PR 1  Project bootstrap + interfaces
PR 2  OracleMath + shared data models
PR 3  Registry + lifecycle + versioning
PR 4  Sequencer + Chainlink price evaluation
PR 5  Strict pricing + Basket NAV
PR 6  Whitelist manifest + generator
PR 7  Live verifier + provenance checks
PR 8  Unit + stock + sequencer tests
PR 9  Fuzz + NAV + identity isolation tests
PR 10 Robinhood fork tests
PR 11 Deployment scripts + CI
PR 12 Operational documentation
```

Each PR SHOULD remain independently reviewable and keep tests passing.

---

# Release Gates

The following MUST be complete before production deployment:

- [ ] Exact V1 token/feed matrix reviewed.
- [ ] Robinhood Stock Token entries independently verified.
- [ ] Crypto wrapper provenance reviewed for every enabled crypto asset.
- [ ] Feed descriptions and decimals validated.
- [ ] Per-asset `maxAge` values explicitly selected.
- [ ] Canonical Robinhood Chain sequencer uptime feed resolved from an authoritative source.
- [ ] Sequencer recovery grace period selected.
- [ ] Full deterministic test suite passes.
- [ ] Fuzz/property suite passes.
- [ ] Robinhood mainnet fork tests pass.
- [ ] Generated manifest equals reviewed configuration.
- [ ] Deployed state matches manifest.
- [ ] Ownership destination reviewed.
- [ ] Candidate assets remain non-enabled unless explicitly approved.

---

# Final Checkpoint

- [ ] 26. Final checkpoint: production readiness
  - Run:
    ```text
    forge fmt --check
    forge build
    forge test
    ```
  - Run whitelist generator.
  - Run whitelist verifier.
  - Run Robinhood Chain fork tests.
  - Compare deployed configuration against manifest.
  - Confirm every enabled asset has:
    - exact token address,
    - exact feed proxy,
    - verified decimals,
    - verified feed description,
    - explicit `maxAge`,
    - correct asset kind,
    - correct pause policy,
    - valid lifecycle state.
  - Confirm no unresolved sequencer placeholder exists.
  - Confirm no automatic DEX fallback exists.
  - Confirm no ticker-based oracle resolution exists.
  - Confirm no crypto wrapper inherits another wrapper's feed.
  - Confirm Stock Token `uiMultiplier()` is not double-applied.
  - Confirm invalid component prices fail strict Basket NAV.
  - Confirm all tests pass before release.
  - _Requirements: 1-14_
