# Robinhood Chainlink feed coverage

Snapshot: 2026-10-09. The [Chainlink Robinhood mainnet feed directory](https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json) lists 58 feeds. The desired [asset manifest](../config/robinhood-mainnet.assets.json) binds 46 of them to exact Robinhood Chain ERC-20 contracts: 36 [Robinhood Stock Tokens](https://api.robinhood.com/rhj/assets) and 10 crypto or stable assets. All 46 are marked `ENABLED` as the intended oracle configuration. The manifest is not proof that a StaticsOracle contract has been deployed or configured. Its sequencer section records the deployed L1 reporter and L2 feed from [PR #19](https://github.com/EqualFiLabs/statics-oracle/pull/19), while `verified` remains false until the recovery grace period and independent review are resolved.

For the stock and ETF rows, generation checks the token contract against Robinhood's active asset registry, the exact Chainlink proxy, onchain code, decimals, answer, staleness, and `oraclePaused()`. SGOV and USAR have Chainlink entity IDs `crypto-RHSGOV` and `crypto-RHUSAR` but no `baseAsset` field; generation checks those exact IDs. The GLD feed's Chainlink metadata identifies the SPDR Gold Shares Robinhood Token.

Seven crypto rows are canonical Robinhood bridge tokens. Generation checks each token's `l1Address()` against the stated Ethereum origin and checks that the [Robinhood L2 Gateway Router](https://docs.robinhood.com/chain/protocol-contracts/) calculates the same L2 token address. LINK uses the [Chainlink-published Robinhood LINK token](https://docs.chain.link/resources/link-token-contracts), rather than a different bridged LINK representation. WETH is the Robinhood protocol WETH contract; USDG is the [Paxos-published Robinhood USDG token](https://docs.paxos.com/guides/stablecoin/usdg/mainnet). The manifest's USDC and EURC are canonical bridges of their Ethereum tokens; Circle does not list Robinhood Chain as a native issuance network in its [supported chains](https://developers.circle.com/circle-mint/supported-chains-and-currencies).

## Feeds without a verified direct asset binding

These 12 directory entries are not in the asset manifest:

| Feed | Reason |
|---|---|
| BTC / USD | BTC itself is not an ERC-20 token on Robinhood Chain. The price cannot be assigned to an arbitrary BTC wrapper. |
| BTC.B / USD | No exact issuer-confirmed Robinhood BTC.B token binding was identified. |
| ENA / USD | No verified Robinhood ENA token binding was identified; the canonical bridge address derived from Ethereum ENA had no code at the snapshot block. |
| LBTC / USD | No verified Robinhood LBTC token binding was identified; the canonical bridge address derived from Ethereum LBTC had no code at the snapshot block. |
| WEETH / USD | No verified Robinhood weETH token binding was identified; the canonical bridge address derived from Ethereum weETH had no code at the snapshot block. |
| USDE / USD | No verified Robinhood USDe token binding was identified; the canonical bridge address derived from Ethereum USDe had no code at the snapshot block. |
| SYRUPUSDC / USD | No verified Robinhood syrupUSDC token binding was identified; the canonical bridge address derived from Ethereum syrupUSDC had no code at the snapshot block. |
| SYRUPUSDC / USDC Exchange Rate | This is a ratio, not a direct USD price. |
| SYRUPUSDT / USDT Exchange Rate | This is a ratio, not a direct USD price. |
| syrupUSDG / USDG Exchange Rate | This is a ratio, not a direct USD price. |
| WEETH / EETH Exchange Rate | This is a ratio, not a direct USD price. |
| WSTETH / STETH Exchange Rate | This is a ratio, not a direct USD price. |

An exchange-rate feed could support a token only after an explicit composite-price design and a verified token address. The current StaticsOracle configuration uses one USD feed per token.

Oracle enablement establishes an exact price binding, not token liquidity. At the snapshot block, the Robinhood bridged cbBTC supply was one base unit, EURC about 2.07 tokens, and USDS about 2.39 tokens. These onchain supplies can change and should not be interpreted as available exit liquidity.
