import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { keccak256 } from "viem";

import { observerSetHash } from "../src/deployment.mjs";
import {
  readMainnetDeployment,
  recordedSequencerConfiguration,
  validateAssetSequencer,
  validateSequencerSnapshots,
  verifyLiveSequencer,
} from "../src/sequencer-config.mjs";

const manifest = JSON.parse(readFileSync(new URL("../../config/robinhood-mainnet.assets.json", import.meta.url)));
const deployment = readMainnetDeployment();
const oldHash = "0x04d01fb3f628cf7fd0130982d87c1ba682525ffe923c6fc229ae0de25a388552";
const otherAddress = "0x0000000000000000000000000000000000001234";

function snapshots() {
  const snapshot = (name, chainId, binding) => ({
    chainId,
    blockNumber: 100n,
    blockHash: `0x${"11".repeat(32)}`,
    observers: deployment.configuration.observers,
    threshold: deployment.configuration.threshold,
    version: 2n,
    binding,
    runtimeCodeHash: deployment.contracts[name].runtimeCodeHash,
  });
  return {
    reporter: snapshot("reporter", 1, deployment.contracts.feed.address),
    feed: snapshot("feed", 4663, deployment.contracts.reporter.address),
  };
}

test("the asset record agrees with the validated deployment and hash", () => {
  const recorded = recordedSequencerConfiguration(deployment);
  validateAssetSequencer(manifest, deployment);
  assert.equal(recorded.observerSetHash, observerSetHash(deployment.configuration.observers, recorded.threshold));
  for (const field of Object.keys(recorded)) assert.equal(recorded[field], manifest.sequencer[field]);
});

test("stale threshold, hash, addresses, and chain IDs fail closed", () => {
  for (const [field, value] of [
    ["threshold", 2], ["threshold", "3"], ["observerSetHash", oldHash],
    ["feed", otherAddress], ["l1Reporter", otherAddress], ["l1Inbox", otherAddress],
  ]) {
    const stale = structuredClone(manifest);
    stale.sequencer[field] = value;
    assert.throws(() => validateAssetSequencer(stale, deployment), new RegExp(`sequencer.${field}`));
  }
  assert.throws(() => validateAssetSequencer({ ...manifest, chainId: 46630 }, deployment), /chainId/);
  assert.throws(() => validateAssetSequencer({ ...manifest, sequencer: null }, deployment));
});

test("generation follows a reviewed rotation and rejects invalid deployment records", () => {
  const reviewed = structuredClone(deployment);
  reviewed.configuration.threshold = 4;
  reviewed.configuration.observerSetHash = observerSetHash(reviewed.configuration.observers, 4);
  assert.equal(recordedSequencerConfiguration(reviewed).threshold, 4);
  assert.equal(recordedSequencerConfiguration(reviewed).observerSetHash, reviewed.configuration.observerSetHash);
  assert.throws(() => validateAssetSequencer(manifest, reviewed), /differs from deployment manifest/);
  reviewed.configuration.observerSetHash = oldHash;
  assert.throws(() => recordedSequencerConfiguration(reviewed), /does not match/);
  reviewed.configuration.threshold = 2;
  assert.throws(() => recordedSequencerConfiguration(reviewed), /strict majority/);
});

test("both chains must match the full reviewed configuration and each other's version", () => {
  validateSequencerSnapshots(snapshots(), deployment);
  for (const name of ["reporter", "feed"]) {
    for (const [field, value, message] of [
      ["chainId", 31337, /chainId mismatch/],
      ["threshold", 2, /threshold differs/],
      ["observers", deployment.configuration.observers.slice(0, 3), /observers differ/],
      ["observers", [...deployment.configuration.observers].reverse(), /observers differ/],
      ["version", 0n, /not initialized/],
      ["version", 3n, /versions differ/],
      ["runtimeCodeHash", oldHash, /runtime code hash differs/],
      ["binding", otherAddress, /binding mismatch/],
    ]) {
      const changed = snapshots();
      changed[name][field] = value;
      assert.throws(() => validateSequencerSnapshots(changed, deployment), message);
    }
  }
});

test("live verification pins every contract/code read and makes no signing calls", async () => {
  const raw = structuredClone(deployment);
  const code = "0x6000";
  for (const contract of Object.values(raw.contracts)) contract.runtimeCodeHash = keccak256(code);
  const calls = [];
  const client = (chainId, bindingFunction, binding) => ({
    getChainId: async () => chainId,
    getBlock: async () => ({ number: 100n, hash: `0x${"11".repeat(32)}` }),
    getCode: async (args) => { calls.push(args); return code; },
    readContract: async (args) => {
      calls.push(args);
      return {
        observers: raw.configuration.observers,
        threshold: raw.configuration.threshold,
        observerSetVersion: 2n,
        [bindingFunction]: binding,
      }[args.functionName];
    },
  });
  const result = await verifyLiveSequencer({
    manifest, deployment: raw,
    clients: {
      ethereum: client(1, "l2Feed", raw.contracts.feed.address),
      robinhood: client(4663, "l1Reporter", raw.contracts.reporter.address),
    },
  });
  assert.equal(result.reporter.version, 2n);
  assert.equal(calls.length, 10);
  assert.ok(calls.every((call) => call.blockNumber === 100n));
  assert.deepEqual(new Set(calls.map((call) => call.address.toLowerCase())), new Set([
    raw.contracts.reporter.address.toLowerCase(), raw.contracts.feed.address.toLowerCase(),
  ]));
});

test("live verification requires both RPCs instead of silently skipping", async () => {
  await assert.rejects(verifyLiveSequencer({ manifest }), /ETH_MAINNET and ROBINHOOD_MAINNET are required/);
  await assert.rejects(verifyLiveSequencer({ manifest, robinhoodRpcUrl: "https://unused.invalid" }), /required/);
});

test("local CLI rejects stale asset metadata without mutating it or needing RPCs", () => {
  const directory = mkdtempSync(join(tmpdir(), "sequencer-config-test-"));
  try {
    const path = join(directory, "assets.json");
    const stale = structuredClone(manifest);
    stale.sequencer.threshold = 2;
    const bytes = JSON.stringify(stale);
    writeFileSync(path, bytes);
    const cli = new URL("../../scripts/verify-sequencer-config.mjs", import.meta.url);
    const result = spawnSync(process.execPath, [cli.pathname, "--manifest", path], { encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /sequencer.threshold differs/);
    assert.equal(readFileSync(path, "utf8"), bytes);
    writeFileSync(path, JSON.stringify(manifest));
    assert.match(execFileSync(process.execPath, [cli.pathname, "--manifest", path], { encoding: "utf8" }), /matches the reviewed deployment/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
