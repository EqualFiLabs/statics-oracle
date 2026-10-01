import assert from "node:assert/strict";
import test from "node:test";

import {
  observerSetHash,
  validateDeploymentManifest,
  validateHealthySnapshot,
} from "../src/deployment.mjs";

const observers = [
  "0x0000000000000000000000000000000000001000",
  "0x0000000000000000000000000000000000002000",
  "0x0000000000000000000000000000000000003000",
];
const address = (suffix) => `0x${suffix.toString(16).padStart(40, "0")}`;
const hash = (suffix) => `0x${suffix.toString(16).padStart(64, "0")}`;

function manifest(deployed = false) {
  return {
    schemaVersion: 1,
    name: "robinhood-testnet",
    source: {
      repository: "https://github.com/EqualFiLabs/statics-oracle",
      commit: "1".repeat(40),
    },
    chains: {
      ethereum: {
        chainId: 11155111,
        deployer: address(1),
        minimumDeployerBalanceWei: "1000000000000000",
        delayedInbox: "0xF2939afA86F6f933A3CE17fCAB007907B6b0B7a4",
        explorer: "https://sepolia.etherscan.io",
      },
      robinhood: {
        chainId: 46630,
        deployer: address(2),
        minimumDeployerBalanceWei: "1000000000000000",
        sequencerFeedUrl: "wss://feed.testnet.chain.robinhood.com",
        explorer: "https://explorer.testnet.chain.robinhood.com",
      },
    },
    contracts: {
      reporter: {
        address: deployed ? address(3) : null,
        deploymentTransaction: deployed ? hash(3) : null,
        runtimeCodeHash: deployed ? hash(4) : null,
      },
      feed: {
        address: deployed ? address(5) : null,
        deploymentTransaction: deployed ? hash(5) : null,
        runtimeCodeHash: deployed ? hash(6) : null,
      },
    },
    configuration: {
      owner: address(7),
      refundAddress: address(8),
      observers,
      threshold: 2,
      observerSetHash: deployed ? observerSetHash(observers, 2) : null,
      statusGasLimit: "200000",
      configurationGasLimit: "400000",
      gasPriceBid: "100000000",
      reserveMessages: 4,
    },
    transactions: {
      funding: deployed ? hash(7) : null,
      initialization: deployed ? hash(8) : null,
    },
    services: { pollIntervalMs: 30000, backupDelayMs: 45000 },
  };
}

test("accepts supported sorted preflight and deployed manifests", () => {
  const preflight = validateDeploymentManifest(manifest());
  assert.equal(preflight.configuration.calculatedObserverSetHash, observerSetHash(observers, 2));
  assert.equal(validateDeploymentManifest(manifest(true), { requireDeployment: true }).configuration.threshold, 2);
});

test("rejects unsafe observer, network, and reserve configuration", () => {
  const unsorted = manifest();
  unsorted.configuration.observers = [observers[1], observers[0], observers[2]];
  assert.throws(() => validateDeploymentManifest(unsorted), /strictly increasing/);

  const weakThreshold = manifest();
  weakThreshold.configuration.threshold = 1;
  assert.throws(() => validateDeploymentManifest(weakThreshold), /strict majority/);

  const wrongFeed = manifest();
  wrongFeed.chains.robinhood.sequencerFeedUrl = "wss://example.invalid";
  assert.throws(() => validateDeploymentManifest(wrongFeed), /supported pair/);

  const lowReserve = manifest();
  lowReserve.configuration.reserveMessages = 3;
  assert.throws(() => validateDeploymentManifest(lowReserve), /at least 4/);

  const numericGasLimit = manifest();
  numericGasLimit.configuration.statusGasLimit = 200000;
  assert.throws(() => validateDeploymentManifest(numericGasLimit), /integer string/);
});

test("healthy snapshot binds both chains and preserves retryable reserve", () => {
  const parsed = validateDeploymentManifest(manifest(true), { requireDeployment: true });
  const snapshot = {
    reporter: {
      owner: parsed.configuration.owner,
      inbox: parsed.chains.ethereum.delayedInbox,
      childChainId: 46630n,
      l2Feed: parsed.contracts.feed.address,
      refundAddress: parsed.configuration.refundAddress,
      statusGasLimit: parsed.configuration.statusGasLimit,
      configurationGasLimit: parsed.configuration.configurationGasLimit,
      gasPriceBid: parsed.configuration.gasPriceBid,
      threshold: 2,
      observers: parsed.configuration.observers,
      observerSetVersion: 1n,
      statusSequence: 1n,
      healthy: true,
      statusQuote: 10n,
      configurationQuote: 20n,
      balance: 80n,
    },
    feed: {
      l1Reporter: parsed.contracts.reporter.address,
      threshold: 2,
      observers: parsed.configuration.observers,
      observerSetVersion: 1n,
      statusSequence: 1n,
      lastHeartbeatStatusSequence: 1n,
      availabilityReason: 1,
      answer: 0n,
      healthyUntil: 1_901n,
    },
  };
  assert.deepEqual(validateHealthySnapshot(snapshot, parsed, 1_000n), {
    requiredBalance: 80n,
    leaseRemaining: 901n,
  });
  snapshot.reporter.balance = 79n;
  assert.throws(() => validateHealthySnapshot(snapshot, parsed, 1_000n), /underfunded/);
  snapshot.reporter.balance = 80n;
  snapshot.feed.healthyUntil = 1_600n;
  assert.throws(() => validateHealthySnapshot(snapshot, parsed, 1_000n), /600 seconds/);
  assert.doesNotThrow(() => validateHealthySnapshot(
    snapshot,
    parsed,
    1_000n,
    { minimumLeaseRemaining: 300n },
  ));
});
