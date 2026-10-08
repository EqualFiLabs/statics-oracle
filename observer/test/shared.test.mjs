import assert from "node:assert/strict";
import test from "node:test";

import {
  AvailabilityTracker,
  LEASE_SECONDS,
  ObserverState,
  requireFreshHeartbeatSample,
  afterBackupDelay,
  heartbeatDue,
  normalizeHeartbeat,
  normalizeStatusReport,
  serializeBigInts,
  validateCrossChainState,
  validateHeartbeat,
  validateHeartbeatSigningProgress,
  validateObservedHeads,
  validateStatusReport,
} from "../src/shared.mjs";

const hash = `0x${"11".repeat(32)}`;
const now = 1_000n;

test("serializes nested preflight quantities without losing structure", () => {
  const report = {
    ethereum: { balance: 10n, chainId: 11_155_111 },
    robinhood: { heads: [2n, { number: 3n }], balance: null },
  };
  assert.deepEqual(serializeBigInts(report), {
    ethereum: { balance: "10", chainId: 11_155_111 },
    robinhood: { heads: ["2", { number: "3" }], balance: null },
  });
});

function validHeartbeatInput() {
  return {
    heartbeat: normalizeHeartbeat({
      observerSetVersion: "4",
      statusSequence: "9",
      observedBlockNumber: "98",
      observedBlockHash: hash,
      validUntil: now + LEASE_SECONDS,
    }),
    expectedObserverSetVersion: 4n,
    expectedStatusSequence: 9n,
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

test("heartbeat signing refreshes a cached sequencer head before validation", async () => {
  const tracker = new AvailabilityTracker();
  for (let index = 0; index < 3; index += 1) tracker.record(true);
  const input = validHeartbeatInput();
  const cached = { ...input, directHead: { ...input.directHead, number: 97n } };
  assert.throws(() => validateHeartbeat(cached), /ahead of the sequencer feed/);

  let sampleCount = 0;
  const sample = await requireFreshHeartbeatSample(async () => {
    sampleCount += 1;
    return {
      directHead: input.directHead,
      directReferenceBlock: input.directReferenceBlock,
      referenceHead: input.referenceHead,
    };
  }, tracker);
  assert.equal(sampleCount, 1);
  assert.doesNotThrow(() => validateHeartbeat({ ...input, ...sample }));
  await assert.rejects(
    requireFreshHeartbeatSample(async () => undefined, tracker),
    /observer is not healthy/,
  );
});

test("backup delay happens before collecting fresh round evidence", async () => {
  const events = [];
  const result = await afterBackupDelay({
    role: "backup",
    delayMs: 45_000,
    sleep: async (delayMs) => events.push(`delay:${delayMs}`),
    action: async () => {
      events.push("collect");
      return "done";
    },
  });
  assert.equal(result, "done");
  assert.deepEqual(events, ["delay:45000", "collect"]);

  let primarySlept = false;
  await afterBackupDelay({
    role: "primary",
    delayMs: 45_000,
    sleep: async () => { primarySlept = true; },
    action: async () => events.push("primary"),
  });
  assert.equal(primarySlept, false);
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

  const staleStatus = validHeartbeatInput();
  staleStatus.heartbeat.statusSequence -= 1n;
  assert.throws(() => validateHeartbeat(staleStatus), /status sequence changed/);
});

test("only the onchain accepted block gates heartbeat signing progress", () => {
  const input = validHeartbeatInput();
  assert.doesNotThrow(() => validateHeartbeatSigningProgress({
    heartbeat: input.heartbeat,
    lastOnchainBlock: 90n,
  }));

  assert.throws(() => validateHeartbeatSigningProgress({
    heartbeat: input.heartbeat,
    lastOnchainBlock: 98n,
  }), /accepted block/);
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
  assert.equal(heartbeatDue(now + 601n, 8n, 8n, now), false);
  assert.equal(heartbeatDue(now + 600n, 8n, 8n, now), true);
});

test("heartbeat renewal is immediately due after a status sequence change", () => {
  assert.equal(heartbeatDue(now + LEASE_SECONDS, 8n, 9n, now), true);
});

test("heartbeat renewal requires L2 configuration and status to match L1", () => {
  const state = {
    l1ObserverSetVersion: 4n,
    l1StatusSequence: 9n,
    l2ObserverSetVersion: 4n,
    l2StatusSequence: 9n,
  };
  assert.doesNotThrow(() => validateCrossChainState(state));
  assert.throws(
    () => validateCrossChainState({ ...state, l2ObserverSetVersion: 3n }),
    /observer set version is behind/,
  );
  assert.throws(
    () => validateCrossChainState({ ...state, l2StatusSequence: 8n }),
    /status sequence is behind/,
  );
});
