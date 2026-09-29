import assert from "node:assert/strict";
import test from "node:test";

import {
  LEASE_SECONDS,
  normalizeObservation,
  validateObservation,
} from "../src/shared.mjs";

const hash = `0x${"11".repeat(32)}`;
const now = 1_000n;

function validInput() {
  return {
    observation: normalizeObservation({
      observerSetVersion: "4",
      observedBlockNumber: "98",
      observedBlockHash: hash,
      validUntil: now + LEASE_SECONDS,
    }),
    expectedObserverSetVersion: 4n,
    directHead: { number: 100n, hash: `0x${"22".repeat(32)}`, timestamp: now - 1n },
    referenceHead: { number: 101n, hash: `0x${"33".repeat(32)}`, timestamp: now - 2n },
    directReferenceBlock: {
      number: 100n,
      hash: `0x${"22".repeat(32)}`,
      timestamp: now - 1n,
    },
    referenceBlock: { number: 98n, hash, timestamp: now - 3n },
    now,
  };
}

test("accepts fresh sequencer-feed progress consistent with the reference RPC", () => {
  assert.doesNotThrow(() => validateObservation(validInput()));
});

test("rejects disagreement between the sequencer feed and reference RPC", () => {
  const input = validInput();
  input.directReferenceBlock.hash = `0x${"44".repeat(32)}`;
  assert.throws(() => validateObservation(input), /disagree/);
});

test("rejects stale sequencer progress", () => {
  const input = validInput();
  input.directHead.timestamp = now - 61n;
  assert.throws(() => validateObservation(input), /direct sequencer-feed head is stale/);
});

test("rejects short and overlong leases", () => {
  const short = validInput();
  short.observation.validUntil = now + 74n;
  assert.throws(() => validateObservation(short), /too short/);

  const long = validInput();
  long.observation.validUntil = now + 96n;
  assert.throws(() => validateObservation(long), /too long/);
});

test("rejects a current-head proposal", () => {
  const input = validInput();
  input.observation.observedBlockNumber = 99n;
  input.directHead.number = 99n;
  input.directHead.hash = hash;
  input.referenceHead.number = 99n;
  input.directReferenceBlock.number = 99n;
  input.directReferenceBlock.hash = hash;
  input.referenceBlock.number = 99n;
  assert.throws(() => validateObservation(input), /not behind the reference head/);
});

test("rejects a proposal ahead of the sequencer feed", () => {
  const input = validInput();
  input.observation.observedBlockNumber = 101n;
  assert.throws(() => validateObservation(input), /ahead of the sequencer feed/);
});
