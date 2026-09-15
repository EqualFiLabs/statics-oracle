# Replacing a Feed

Feed replacement is an explicit owner-controlled migration. A Chainlink or Robinhood
directory change may reveal drift, but it must never mutate protocol configuration or
automatically select a replacement.

The only permitted lifecycle is:

```text
ENABLED
-> DISABLED
-> update binding
-> CANDIDATE
-> verify
-> ENABLED
```

`updateAsset` rejects an enabled binding and writes the replacement back as `CANDIDATE`,
so the contract enforces the safety-critical parts of this sequence.

## Procedure

1. Record why replacement is needed and capture the current token, feed, config hash,
   registry version, and owner.
2. Validate the exact replacement proxy from authoritative Chainlink and Robinhood sources.
   At a pinned block, verify bytecode, feed decimals, description hash, positive complete
   round data, timestamp, freshness, and any token pause state.
3. Review the proposed `maxAge`, feed description, asset kind, and pause policy. A proxy
   change is not assumed to preserve metadata or risk characteristics.
4. Submit `disableAsset(token)`. Confirm the `ENABLED -> DISABLED` event and exact version
   increment. Protected price and NAV reads must now fail closed for that asset.
5. Submit `updateAsset(token, replacementConfig)`. Confirm `AssetUpdated`, the emitted
   config hash, `DISABLED -> CANDIDATE`, and one additional version increment.
6. Independently compare every deployed field and the registry version to the reviewed
   proposal. Run the live verifier and relevant fork tests. If the checked-in matrix has
   changed, regenerate it from the reviewed source rather than editing it by hand.
7. Leave the asset as `CANDIDATE` while reviewers assess source provenance, wrapper
   identity, round behavior, freshness policy, and operational readiness.
8. Submit `enableAsset(token)` only after explicit approval. The contract revalidates the
   stored token/feed identity and current live conditions before emitting
   `CANDIDATE -> ENABLED`.
9. Verify the final fields, config hash, lifecycle state, version, events, and strict price.
   Preserve the old and new evidence for incident review.

## Failure and rollback

If verification fails before re-enablement, keep the asset `CANDIDATE` or move it to
`DISABLED`; do not bypass the failure with a generic feed or DEX price. If a newly enabled
feed behaves incorrectly, disable the asset immediately and reassess. Returning to the old
feed is itself another reviewed replacement through the same disabled/candidate lifecycle.

The scheduled workflow is intentionally read-only. It reports source or live-contract
drift but neither changes the manifest nor submits owner transactions. Human review is the
boundary between external information and protocol configuration.

