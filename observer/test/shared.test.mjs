import assert from "node:assert/strict";
import test from "node:test";

import {
  AvailabilityTracker,
  LEASE_SECONDS,
  ObserverState,
  heartbeatDue,
  normalizeHeartbeat,
  normalizeStatusReport,
  validateHeartbeat,
  validateObservedHeads,
  validateStatusReport,
} from "../src/shared.mjs";

const hash = `0x${"11".repeat(32)}`;
const now = 1_000n;

function validHeartbeatInput() {
  return {
    heartbeat: normalizeHeartbeat({
      observerSetVersion: "4",
      observedBlockNumber: "98",
      observedBlockHash: hash,
      validUntil: now + LEASE_SECONDS,
    }),
    expectedObserverSetVersion: 4n,
    directHead: { number: 100n, hash: `0x${"22".repeat(32)}`, timestamp: now - 1n },
    referenceHead: { number: 101n, hash: `0x${"33".repeat(32)}`, timestamp: now - 2n },
    directReferenceBlock: { number: 100n, hash: `0x${"22".repeat(32)}`, timestamp: now - 1n },
    referenceBlock: { number: 98n, hash, timestamp: now - 3n },
    now,
  };
}

test("requires three consecutive samples for impairment and recovery", () => {
  const tracker = new AvailabilityTracker();
  tracker.record(true);
  tracker.record(true);
  assert.equal(tracker.state, ObserverState.UNKNOWN);
  tracker.record(true);
  assert.equal(tracker.state, ObserverState.HEALTHY);
  tracker.record(false, 1, new Error("one"));
  tracker.record(false, 2, new Error("two"));
  assert.equal(tracker.state, ObserverState.HEALTHY);
  tracker.record(false, 3, new Error("three"));
  assert.equal(tracker.state, ObserverState.IMPAIRED);
  tracker.record(true);
  tracker.record(true);
  assert.equal(tracker.state, ObserverState.IMPAIRED);
  tracker.record(true);
  assert.equal(tracker.state, ObserverState.HEALTHY);
});

test("restart starts unknown", () => {
  const tracker = new AvailabilityTracker();
  assert.equal(tracker.snapshot().state, ObserverState.UNKNOWN);
});

test("accepts fresh direct and reference evidence with a 15 minute lease", () => {
  assert.doesNotThrow(() => validateHeartbeat(validHeartbeatInput()));
});

test("rejects disagreement and overlong leases", () => {
  const disagreement = validHeartbeatInput();
  disagreement.directReferenceBlock.hash = `0x${"44".repeat(32)}`;
  assert.throws(() => validateHeartbeat(disagreement), /disagree/);

  const overlong = validHeartbeatInput();
  overlong.heartbeat.validUntil += 1n;
  assert.throws(() => validateHeartbeat(overlong), /too long/);
});

test("rejects future-dated heads before local recovery", () => {
  const input = validHeartbeatInput();
  input.directHead.timestamp = now + 16n;
  input.directReferenceBlock.timestamp = now + 16n;
  assert.throws(() => validateObservedHeads(input), /future/);

  const referenceFuture = validHeartbeatInput();
  referenceFuture.referenceHead.timestamp = now + 16n;
  assert.throws(() => validateObservedHeads(referenceFuture), /future/);
});

test("status report must match confirmed local state and next L1 sequence", () => {
  const report = normalizeStatusReport({
    observerSetVersion: 2,
    sequence: 8,
    healthy: true,
    observedAt: now,
    validUntil: now + 300n,
  });
  assert.doesNotThrow(() => validateStatusReport({
    report,
    version: 2n,
    sequence: 7n,
    currentHealthy: false,
    localState: ObserverState.HEALTHY,
    now,
  }));
  assert.throws(() => validateStatusReport({
    report,
    version: 2n,
    sequence: 7n,
    currentHealthy: false,
    localState: ObserverState.IMPAIRED,
    now,
  }), /disagrees/);
});

test("heartbeat renewal becomes due with ten minutes remaining", () => {
  assert.equal(heartbeatDue(now + 601n, now), false);
  assert.equal(heartbeatDue(now + 600n, now), true);
});
