# Requirements Document

## Introduction

The Robinhood Chain Oracle Whitelist provides Statics with a trusted, deterministic USD pricing layer for external assets used inside Statics Baskets.

The system SHALL maintain an explicit mapping between each supported Robinhood Chain token contract and its approved Chainlink Data Feed proxy. It SHALL expose normalized USD prices suitable for calculating the net asset value of Statics Baskets while preventing ticker-based ambiguity, incorrect wrapper pricing, stale oracle usage, corporate-action inconsistencies, and accidental use of unapproved price sources.

The initial scope covers Robinhood Stock Tokens, ETFs, and selected crypto assets on Robinhood Chain mainnet, chain ID `4663`.

Pricing of the STATICS token itself, Basket Token TWAPs, Morpho risk parameters, DEX fallback pricing, and Chainlink Data Streams are outside the scope of this specification.

## Glossary

**Asset**  
An ERC-20 token on Robinhood Chain that may be used as a Statics Basket underlying.

**Basket**  
A Statics Basket ERC-20 representing fixed amounts of one or more underlying assets.

**Basket NAV**  
The USD value of the fixed underlying asset amounts required to mint one Basket Token.

**Canonical Token**  
The exact Robinhood Chain token contract approved to represent a particular asset.

**Chainlink Feed**  
A Chainlink Data Feed proxy implementing the `AggregatorV3Interface` pricing interface.

**Feed Proxy**  
The stable Chainlink proxy address through which Statics reads an asset's oracle price. The underlying aggregator implementation is not considered the canonical integration address.

**Token/Feed Binding**  
The explicit association of one token contract with one approved Chainlink feed proxy.

**Stock Token**  
A Robinhood-issued ERC-20 providing economic exposure to an underlying equity.

**ETF Token**  
A Robinhood-issued ERC-20 providing economic exposure to an exchange-traded fund.

**Crypto Wrapper**  
An ERC-20 representing a crypto asset or derivative of a crypto asset, such as WBTC, cbBTC, or wstETH.

**Multiplier**  
Robinhood Stock Token `uiMultiplier()` data used by Robinhood and Chainlink to account for dividends, splits, and other corporate actions.

**Oracle Pause**  
The `oraclePaused()` state exposed by Robinhood Stock Tokens during certain corporate-action workflows.

**Stale Price**  
A feed result whose `updatedAt` timestamp violates the configured freshness policy for that asset.

**Normalized USD Price**  
The USD value of one token expressed at a common precision suitable for aggregation across assets.

**Enabled Asset**  
An approved asset whose token/feed binding may currently be consumed by Statics.

**Candidate Asset**  
An asset whose token/feed pair has been identified but SHALL NOT become enabled until all required provenance and risk checks have been completed.

---

## Requirements

### Requirement 1: Robinhood Chain Scope

**User Story:** As a Statics protocol integrator, I want the oracle system to operate against one explicitly defined network and quote currency, so that asset pricing cannot accidentally mix data from different deployments.

#### Acceptance Criteria

1. THE Oracle System SHALL target Robinhood Chain mainnet with chain ID `4663`.
2. THE Oracle System SHALL express external asset reference prices in USD.
3. THE Oracle System SHALL use Chainlink Data Feeds as the primary external price source for assets covered by this specification.
4. THE Oracle System SHALL NOT treat a feed or token deployment on another blockchain as valid for Robinhood Chain.
5. IF the runtime chain ID does not match the expected deployment configuration, THEN deployment or validation tooling SHALL fail rather than silently accepting the mismatch.

---

### Requirement 2: Exact Token/Feed Whitelisting

**User Story:** As a Statics risk manager, I want every supported asset to be identified by its exact token contract and exact oracle feed, so that ticker collisions and lookalike tokens cannot obtain valid pricing.

#### Acceptance Criteria

1. THE Oracle System SHALL identify each supported asset by token contract address.
2. THE Oracle System SHALL bind each supported token contract to exactly one approved price-feed configuration at a time.
3. THE Oracle System SHALL treat symbols and token names as metadata only.
4. THE Oracle System SHALL NOT authorize an asset based solely on symbol, name, ticker, DEX market, or economic equivalence.
5. WHEN an unapproved token shares a symbol with an approved token, THE Oracle System SHALL treat the unapproved token as unsupported.
6. WHEN two wrappers represent the same economic asset, THE Oracle System SHALL treat them as independent assets requiring independent token/feed bindings.
7. THE initial approved and candidate bindings SHALL conform to Appendix A.

---

### Requirement 3: Canonical Source Verification

**User Story:** As a protocol operator, I want every whitelist entry checked against canonical data sources, so that configuration errors or third-party token lists cannot silently introduce incorrect assets.

#### Acceptance Criteria

1. BEFORE a Stock Token or ETF Token is enabled, THE validation process SHALL confirm the token against Robinhood's asset data.
2. BEFORE any asset is enabled, THE validation process SHALL confirm its feed proxy against Chainlink's Robinhood Chain feed data.
3. THE validation process SHALL treat Robinhood `/rhj/assets` as the canonical issuer source for Robinhood Stock Token identity.
4. THE validation process SHALL treat Chainlink's Robinhood mainnet feed directory and official Chainlink feed documentation as canonical sources for feed identity.
5. THE validation process SHALL NOT treat Blockscout search results, DEX pools, third-party token lists, or ticker matching alone as sufficient evidence for an enabled binding.
6. IF canonical sources disagree about an asset or feed, THEN the asset SHALL NOT become enabled until the discrepancy is explicitly resolved.
7. WHEN validating an asset, THE system SHALL verify that the configured token and feed addresses contain contract code on chain `4663`.
8. WHEN validating a token, THE system SHALL compare its reported decimals and identifying metadata with the expected configuration.
9. WHEN validating a feed, THE system SHALL compare its description and decimals with the expected asset/feed binding.

---

### Requirement 4: Robinhood Stock and ETF Pricing

**User Story:** As a Basket NAV consumer, I want Robinhood Stock Tokens priced according to their actual token value, so that dividends, splits, and other corporate actions are reflected correctly.

#### Acceptance Criteria

1. WHEN pricing a supported Robinhood Stock Token or ETF Token, THE Oracle System SHALL consume the approved Chainlink tokenized-equity feed.
2. THE Oracle System SHALL treat the Chainlink feed result as the multiplier-adjusted price of one token.
3. THE Oracle System SHALL NOT multiply the Chainlink feed result by `uiMultiplier()` a second time.
4. WHEN Robinhood changes `uiMultiplier()` as part of a dividend, split, or other corporate action, THE Oracle System SHALL continue using the Chainlink-reported token price without independently reconstructing the corporate action.
5. THE Oracle System SHALL support different feed precisions and SHALL NOT assume that all future stock feeds use the same number of decimals.
6. WHEN a supported Stock Token reports `oraclePaused() == true`, THE Oracle System SHALL treat its live price as unavailable for state-changing Statics operations.
7. THE Oracle System SHALL retain sufficient oracle status information for consumers to distinguish a corporate-action pause from a normal valid price.

---

### Requirement 5: Crypto Asset Pricing

**User Story:** As a Statics risk manager, I want crypto wrappers priced according to their exact approved representation, so that the protocol does not confuse economically related but technically different assets.

#### Acceptance Criteria

1. EACH supported crypto token SHALL have its own explicit token/feed binding.
2. THE Oracle System SHALL NOT automatically assign the generic `BTC/USD` price to arbitrary Bitcoin wrappers.
3. THE Oracle System SHALL NOT automatically assign the generic `ETH/USD` price to arbitrary Ethereum derivatives or wrappers unless that exact binding has been approved.
4. WHEN WBTC is enabled, THE Oracle System SHALL use the explicitly approved WBTC configuration rather than infer pricing from another Bitcoin token.
5. WHEN cbBTC is enabled, THE Oracle System SHALL use the explicitly approved cbBTC configuration rather than infer pricing from WBTC or another Bitcoin representation.
6. WHEN wstETH is enabled, THE Oracle System SHALL use its explicitly approved pricing configuration rather than infer pricing from WETH.
7. Candidate crypto assets SHALL remain unavailable to production Basket creation until their canonical token provenance and enablement status have been explicitly approved.

---

### Requirement 6: Feed Integrity and Freshness

**User Story:** As a Statics user, I want Basket valuations to reject invalid or stale oracle results, so that protocol actions cannot execute against known-bad prices.

#### Acceptance Criteria

1. WHEN reading an approved feed, THE Oracle System SHALL require a positive price.
2. WHEN a feed reports zero or a negative price, THE Oracle System SHALL reject the result.
3. WHEN `updatedAt == 0`, THE Oracle System SHALL reject the result.
4. WHEN a Chainlink round is incomplete, THE Oracle System SHALL reject the result.
5. EACH enabled asset SHALL have an explicit freshness policy.
6. WHEN a feed result exceeds the asset's permitted age, THE Oracle System SHALL reject the result as stale.
7. THE freshness policy SHALL be configurable per asset or feed and SHALL NOT rely on one universal hardcoded timeout for every asset class.
8. THE system SHALL preserve the feed's round and timestamp metadata for diagnostics.
9. THE Oracle System SHALL read through the approved Chainlink feed proxy rather than pinning an underlying aggregator implementation.

---

### Requirement 7: Robinhood L2 Sequencer Safety

**User Story:** As a protocol user, I want oracle prices rejected when the Robinhood Chain sequencer state makes them unsafe to consume, so that stale L2 state cannot be treated as live market data.

#### Acceptance Criteria

1. BEFORE production enablement of sequencer protection, THE canonical Robinhood Chain L2 Sequencer Uptime Feed SHALL be independently resolved and verified.
2. WHEN the configured sequencer feed reports that the sequencer is down, THE Oracle System SHALL treat external prices as unavailable for protected state-changing operations.
3. WHEN the sequencer has recently recovered, THE Oracle System SHALL enforce a configured recovery grace period before treating prices as live.
4. THE Oracle System SHALL NOT fabricate or assume a sequencer-feed address.
5. IF sequencer protection is required but its configuration is missing or invalid, THEN protected state-changing price reads SHALL fail closed.

---

### Requirement 8: Normalized USD Price Surface

**User Story:** As a Statics integration developer, I want every supported asset exposed through one consistent USD pricing surface, so that Basket NAV calculation does not need asset-specific oracle logic.

#### Acceptance Criteria

1. THE Oracle System SHALL expose the USD price of a supported token at a common precision.
2. THE common precision SHALL be sufficient to safely aggregate assets with differing token and feed decimals.
3. A normalized price response SHALL identify whether the price is valid for protocol use.
4. A normalized price response SHALL make relevant oracle timestamp/status metadata available to consumers.
5. WHEN the token is unsupported or disabled, THE Oracle System SHALL NOT return that token as a valid priced asset.
6. WHEN the underlying oracle is invalid under Requirements 4, 6, or 7, THE normalized price surface SHALL report failure rather than silently returning a fallback market price.
7. THE Oracle System SHALL NOT silently substitute DEX spot pricing when an approved Chainlink source is invalid.

---

### Requirement 9: Basket NAV Compatibility

**User Story:** As the Statics Basket system, I want to value fixed Basket compositions using normalized asset prices, so that one oracle layer works across all supported Basket combinations.

#### Acceptance Criteria

1. THE Oracle System SHALL support NAV calculation for Basket compositions expressed as fixed token amounts.
2. FOR each Basket underlying, THE USD contribution SHALL equal the normalized USD value of the configured underlying amount.
3. THE Basket NAV SHALL equal the sum of the USD contributions of all supported underlying assets.
4. THE Oracle System SHALL correctly account for each underlying token's own decimals.
5. THE Oracle System SHALL correctly account for each feed's own decimals before aggregation.
6. THE Oracle System SHALL NOT require percentage weights or rebalancing metadata in order to value a static Statics Basket.
7. IF any required Basket underlying lacks a valid oracle price, THEN the Basket SHALL NOT be reported as having a valid live NAV for protected state-changing operations.
8. THE oracle layer SHALL remain independent of Statics Basket mint/redeem fee calculations unless a later specification explicitly adds such behavior.

---

### Requirement 10: Whitelist Lifecycle

**User Story:** As a Statics administrator, I want supported assets to have explicit lifecycle states, so that assets can be prepared, enabled, disabled, or replaced without silently changing pricing assumptions.

#### Acceptance Criteria

1. THE Oracle System SHALL distinguish between unsupported, candidate, enabled, and disabled asset states.
2. A candidate asset SHALL NOT be treated as valid for production Basket pricing.
3. ONLY an enabled asset SHALL be valid for protected production pricing operations.
4. WHEN an enabled asset is disabled, THE Oracle System SHALL stop treating its price as valid for protected state-changing operations.
5. CHANGING the feed associated with an existing token SHALL require an explicit configuration change.
6. THE Oracle System SHALL NOT silently replace a token/feed binding because an external directory changed.
7. Historical configuration records SHALL make it possible to determine which token/feed binding was approved at a given configuration version.
8. Adding or removing an asset SHALL follow a documented validation procedure.

---

### Requirement 11: Machine-Readable Whitelist Provenance

**User Story:** As a developer or auditor, I want the approved oracle matrix stored in a reproducible machine-readable form, so that deployed configuration can be traced back to its sources.

#### Acceptance Criteria

1. THE project SHALL maintain a machine-readable representation of the approved asset matrix.
2. EACH matrix entry SHALL include at minimum the token address, feed proxy, token decimals, feed decimals, asset classification, lifecycle status, and applicable freshness configuration.
3. EACH generated or verified matrix SHALL record the canonical source locations used for validation.
4. EACH generated or verified matrix SHALL record when the validation was performed.
5. WHERE onchain validation is used, THE matrix or accompanying provenance data SHALL record the relevant verification block or equivalent reproducibility metadata.
6. THE generated matrix SHALL be suitable for automated validation during tests or deployment tooling.
7. THE repository SHALL document the process for regenerating and reviewing the matrix.

---

### Requirement 12: Explicit Failure Semantics

**User Story:** As an integrating protocol, I want oracle failures to be distinguishable, so that Statics can react safely and operators can diagnose the cause.

#### Acceptance Criteria

1. THE Oracle System SHALL distinguish an unsupported token from a supported but disabled token.
2. THE Oracle System SHALL distinguish missing oracle configuration from an invalid oracle result.
3. THE Oracle System SHALL distinguish zero or negative price failures.
4. THE Oracle System SHALL distinguish incomplete Chainlink rounds.
5. THE Oracle System SHALL distinguish stale prices.
6. THE Oracle System SHALL distinguish Robinhood Stock Token oracle pauses.
7. THE Oracle System SHALL distinguish sequencer-unavailable conditions.
8. THE Oracle System SHALL distinguish sequencer-recovery grace-period conditions.
9. THE Oracle System SHALL reject token/feed identity mismatches.
10. THE Oracle System SHALL provide deterministic failure behavior suitable for both smart-contract testing and production monitoring.

---

### Requirement 13: Verification and Regression Coverage

**User Story:** As a Statics developer, I want the oracle invariants covered by automated tests, so that future changes cannot silently weaken pricing safety.

#### Acceptance Criteria

1. TESTS SHALL prove that a same-symbol lookalike token cannot use the feed of an approved token.
2. TESTS SHALL prove that crypto wrappers do not inherit feeds based on economic equivalence.
3. TESTS SHALL prove that feed decimals are normalized correctly.
4. TESTS SHALL prove that token decimals are normalized correctly.
5. TESTS SHALL prove that a Robinhood Stock Token's `uiMultiplier()` is not applied twice.
6. TESTS SHALL cover stock-price continuity across representative dividend or split multiplier changes.
7. TESTS SHALL cover zero, negative, incomplete, stale, and paused oracle results.
8. TESTS SHALL cover unsupported and disabled assets.
9. TESTS SHALL cover incorrect token/feed bindings.
10. TESTS SHALL cover sequencer-down and sequencer-recovery behavior once the canonical sequencer feed is configured.
11. TESTS SHALL cover multi-asset Basket NAV calculation using assets with different token and feed decimal configurations.

---

### Requirement 14: V1 Scope Boundaries

**User Story:** As a protocol maintainer, I want this feature to remain narrowly scoped, so that external-asset oracle infrastructure can be completed and audited before additional pricing systems are introduced.

#### Acceptance Criteria

1. THIS specification SHALL NOT define the oracle mechanism for the STATICS token.
2. THIS specification SHALL NOT define Basket Token TWAP pricing.
3. THIS specification SHALL NOT define Morpho LLTV or lending-market risk parameters.
4. THIS specification SHALL NOT introduce DEX spot pricing as an automatic fallback for Chainlink.
5. THIS specification SHALL NOT require Chainlink Data Streams.
6. THIS specification SHALL NOT define dynamic Basket rebalancing.
7. Future pricing mechanisms MAY consume the normalized pricing architecture defined here, but SHALL require separate specifications where their trust assumptions differ.

---

## Appendix A: Initial Asset Matrix

### A.1 Enabled V1 Stock and ETF Assets

| Asset | Type | Robinhood Chain Token | Chainlink USD Feed Proxy | Initial Status |
|---|---|---|---|---|
| AAPL | Stock | `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9` | `0x6B22A786bAa607d76728168703a39Ea9C99f2cD0` | Enabled target |
| NVDA | Stock | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` | `0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15` | Enabled target |
| MSFT | Stock | `0xe93237C50D904957Cf27E7B1133b510C669c2e74` | `0x45C3C877C15E6BA2EBB19eA114Ea508d14C1Af2E` | Enabled target |
| GOOGL | Stock | `0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3` | `0xF6f373a037c30F0e5010d854385cA89185AE638b` | Enabled target |
| AMZN | Stock | `0x12f190a9F9d7D37a250758b26824B97CE941bF54` | `0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C` | Enabled target |
| META | Stock | `0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35` | `0x7C38C00C30BEe9378381E7B6135d7283356D71b1` | Enabled target |
| TSLA | Stock | `0x322F0929c4625eD5bAd873c95208D54E1c003b2d` | `0x4A1166a659A55625345e9515b32adECea5547C38` | Enabled target |
| AMD | Stock | `0x86923f96303D656E4aa86D9d42D1e57ad2023fdC` | `0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72` | Enabled target |
| PLTR | Stock | `0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A` | `0x820ABedFF239034956B7A9d2F0a331f9F075eB4c` | Enabled target |
| COIN | Stock | `0x6330D8C3178a418788dF01a47479c0ce7CCF450b` | `0xA3a468A452940B7D6b69991207B508c609a98Ef2` | Enabled target |
| MSTR | Stock | `0xec262a75e413fAfD0dF80480274532C79D42da09` | `0x396118bdFB181e6240E74D243F266B061c0edc3D` | Enabled target |
| CRCL | Stock | `0xdF0992E440dD0be65BD8439b609d6D4366bf1CB5` | `0x6652eDf64bA3731C4F2D3ce821A0Fb1f1f6b482a` | Enabled target |
| ORCL | Stock | `0xb0992820E760d836549ba69BC7598b4af75dEE03` | `0x0e6a64a2B58A6693a531E6c555f3A5d042eEA844` | Enabled target |
| SPY | ETF | `0x117cc2133c37B721F49dE2A7a74833232B3B4C0C` | `0x319724394D3A0e3669269846abE664Cd621f9f6A` | Enabled target |
| QQQ | ETF | `0xD5f3879160bc7c32ebb4dC785F8a4F505888de68` | `0x80901d846d5D7B030F26B480776EE3b29374C2ae` | Enabled target |

### A.2 Crypto Assets

| Asset | Robinhood Chain Token | Chainlink USD Feed Proxy | Token Decimals | Initial Status |
|---|---|---|---:|---|
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | `0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9` | 18 | Enabled target |
| USDG | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | `0x61B7e5650328764B076A108EFF5fa7282a1B9aD2` | 6 | Enabled target |
| LINK | `0x492641f648a4986844848e0befe66d14817bce34` | `0xe86e3422Aa9B5e8ee9f3E41a63975bC387A8bce9` | 18 | Candidate |
| WBTC | `0x6bac06600D220Ac5Ac281AD1f504D2Cf0F90F6e6` | `0x62107b0d3adA75fc1697fD342d99eed947a3aA5E` | 8 | Candidate |
| cbBTC | `0xd3FCec4E6C6bF5D7369A912Dd52AB810F9b266d1` | `0x0009cD492adf8167f9eEBf1293556A673530a21a` | 8 | Candidate |
| USDC | `0x80e0e24718dbFcad49ECAA6F1e6C89A190586cA8` | `0x9e6f4605992a899eE2999999F3Ec80C41F452546` | 6 | Candidate |
| USDT | `0xE246BC49b0598d7Cd9f0eAD48B885034f1254380` | `0xbf3550B6fAe1671da7C238Af12e03Ac586BEf3B1` | 6 | Candidate |
| wstETH | `0xcD26A6AA5BB008240A998E242F51232FE98B12Cb` | `0x3F5040B50FB37934573B210fE54B53a6F1A792E8` | 18 | Candidate |

## Canonical References

- Robinhood Asset API: `https://api.robinhood.com/rhj/assets`
- Robinhood Oracle Documentation: `https://docs.robinhood.com/chain/oracles-and-price-feeds/`
- Chainlink Robinhood Feed Directory: `https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json`
- Chainlink Robinhood Tokenized Equity Documentation: `https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`
- Chainlink Data Feed Address Catalog: `https://docs.chain.link/data-feeds/price-feeds/addresses`
