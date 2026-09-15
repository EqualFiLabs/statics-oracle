# Adding an Asset

Adding an asset is a governance and risk decision, not a ticker lookup. The exact token
contract, exact feed proxy, lifecycle state, and policy fields must be reviewed together.
An asset starts as `CANDIDATE`; it does not become usable merely because it appears in an
external directory or the checked-in manifest.

## Procedure

1. **Identify the exact token contract.** Record the Robinhood mainnet address, chain ID
   `4663`, bytecode presence, decimals, kind, and intended symbol. Never infer identity from
   `symbol()` or `name()`.
2. **Verify Robinhood provenance where applicable.** Match Stock Tokens and ETFs against
   Robinhood's canonical deployment data by address and asset identity. Confirm that
   `oraclePaused()` is callable and currently false. Preserve the source URL and retrieval
   block/time in the review evidence.
3. **Identify the exact Chainlink proxy.** Match the token's base asset and USD quote in
   Chainlink's canonical directory. Use the proxy deployed on Robinhood Chain, not a feed
   from another chain and not a generic feed borrowed from a related wrapper.
4. **Verify the contracts.** At a pinned block, check code at both addresses, token and feed
   decimals, the feed description and its hash, a positive complete round, a non-future
   timestamp, and freshness against the proposed `maxAge`.
5. **Assess wrapper provenance.** For crypto and stable assets, document why this exact
   wrapper is approved. WBTC, cbBTC, bridged assets, and liquid-staking derivatives are
   independent assets even when they share an economic reference. Approval of one does not
   approve another.
6. **Select policy explicitly.** Choose `kind`, `maxAge`, `checkOraclePause`, and target
   lifecycle status. `maxAge` must be justified from the published heartbeat and protocol
   risk tolerance. Stock and ETF entries require `checkOraclePause: true`.
7. **Update the reviewed source.** Amend the public whitelist issue and the generator's
   issue-seed matrix in the same proposal. A local manifest-only edit is not authoritative.
8. **Generate deterministically.** Using an authorized private, archive-capable RPC, run:

   ```bash
   node scripts/generate-whitelist.mjs --block <reviewed-block>
   ```

   Review the source identities, live evidence, desired lifecycle status, and diff. Commit
   the generated manifest; do not hand-edit generated fields.
9. **Register as a candidate.** Submit the owner transaction that registers the exact
   configuration. Confirm the `AssetRegistered` and `AssetStatusChanged` events, the
   config hash, and a one-step `registryVersion` increment. Do not bundle enablement into
   the same unreviewed decision.
10. **Verify live and on a fork.** Run:

    ```bash
    node scripts/verify-whitelist.mjs
    forge test --match-path 'test/fork/*.t.sol'
    ```

    Compare the deployed candidate fields to the manifest. Resolve every hard failure and
    review every warning.
11. **Obtain explicit approval.** Review exact token/feed provenance, decimals,
    description, freshness, pause policy, sequencer safety, owner destination, and wrapper
    risk. Candidate crypto assets remain candidates unless separately approved.
12. **Enable explicitly.** Only after all gates pass, submit `enableAsset(token)`. The
    contract rechecks identity, pause state, sequencer health, and the current feed round.
    Confirm the `CANDIDATE -> ENABLED` event and exact registry-version increment.

## Abort conditions

Stop instead of registering or enabling if the token or feed identity is ambiguous, the
source directories disagree, code or metadata is missing, the feed round is invalid or
stale, a Stock Token is paused, wrapper provenance is unresolved, the `maxAge` lacks a risk
review, or the canonical onchain sequencer guard is not configured and healthy.

