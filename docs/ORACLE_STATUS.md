# Oracle Status and Operator Response

`peekPrice(token)` returns diagnostic `PriceData` without reverting. `priceUsd`,
`valueUsd`, and every component of `basketNav` are strict: only `VALID` is accepted, and
all other statuses revert. Strict Basket NAV never omits or substitutes a failing
component.

| `OracleStatus` | Meaning | Strict behavior | Operator response |
| --- | --- | --- | --- |
| `VALID` | Asset is enabled; sequencer, pause check, feed round, timestamp, and freshness all pass. | Returns an 18-decimal USD price; NAV includes the component. | Continue monitoring. Treat validity as point-in-time, not permanent approval. |
| `UNSUPPORTED` | No configuration exists for the exact token address. | `UnsupportedAsset(token)`. | Check the caller's exact address. Use the asset-addition process; never resolve by ticker. |
| `CANDIDATE` | Binding exists but has not been approved for production pricing. | `AssetNotEnabled(token, CANDIDATE)`. | Complete provenance, policy, live, fork, and governance review before explicit enablement. |
| `DISABLED` | The owner has removed the asset from protected pricing. | `AssetNotEnabled(token, DISABLED)`. | Keep dependent actions halted. Diagnose the disablement reason before any candidate transition. |
| `SEQUENCER_NOT_CONFIGURED` | No uptime-feed proxy is configured. | `SequencerNotConfigured()`. | Do not enable or consume production pricing. Resolve the canonical onchain feed and reviewed grace period. |
| `SEQUENCER_DOWN` | The feed reports down, is malformed, cannot be called, or has an invalid start time. | `SequencerDown()`. | Halt protected operations. Verify chain and feed health; wait for an authoritative recovery signal. |
| `SEQUENCER_GRACE_PERIOD` | The sequencer reports up but the configured recovery delay has not elapsed. | `SequencerGracePeriod(recoveryStartedAt, gracePeriod)`. | Keep operations halted until the full boundary has elapsed, then re-evaluate fresh data. |
| `STOCK_ORACLE_PAUSED` | A Stock Token or ETF reports `oraclePaused() == true`. | `StockOraclePaused(token)`. | Halt the asset and investigate Robinhood's corporate-action/oracle state. Do not reconstruct price locally. |
| `STOCK_PAUSE_CHECK_FAILED` | The required `oraclePaused()` call reverted or returned malformed data. | `StockPauseCheckFailed(token)`. | Treat as unavailable. Verify exact token bytecode/interface and upstream health. |
| `FEED_CALL_FAILED` | `latestRoundData()` reverted or returned malformed data. | `FeedCallFailed(feed)`. | Verify the exact proxy, chain state, and upstream incident. Do not substitute a fallback feed. |
| `INVALID_PRICE` | Feed answer is zero, negative, or too large to normalize safely. | `InvalidPrice(feed)`. | Halt use and investigate the feed. Do not clamp, take an absolute value, or reuse an old answer. |
| `INCOMPLETE_ROUND` | Timestamp is zero or `answeredInRound < roundId`. | `IncompleteRound(feed, roundId)`. | Wait for a complete round and verify feed health before retrying. |
| `INVALID_TIMESTAMP` | Feed timestamp is in the future relative to the chain. | `InvalidOracleTimestamp(feed, updatedAt)`. | Treat as feed/chain-time corruption; inspect the proxy and chain before resuming. |
| `STALE_PRICE` | `block.timestamp - updatedAt` exceeds the asset's explicit `maxAge`. | `StalePrice(feed, updatedAt, maxAge)`. | Halt use. Determine whether the feed is delayed or the reviewed freshness policy is wrong; policy changes require full review. |

Sequencer evaluation precedes per-asset feed evaluation. Consequently a sequencer status
can mask an asset-level status until the global guard is healthy. For multi-asset NAV, the
sequencer is evaluated once and the first invalid component encountered causes the whole
strict read to revert.

Statuses are diagnostic classifications, not permission to automate a remediation. The
safe default is to preserve or move the affected asset to a non-enabled state, establish
the source-backed cause, and use the documented addition or replacement lifecycle.
