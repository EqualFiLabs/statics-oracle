import { encodeAbiParameters, getAddress, keccak256, zeroAddress } from "viem";

export const DEPLOYMENT_PAIRS = Object.freeze({
  "1:4663": Object.freeze({
    delayedInbox: getAddress("0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D"),
    sequencerFeedUrl: "wss://feed.mainnet.chain.robinhood.com",
  }),
  "11155111:46630": Object.freeze({
    delayedInbox: getAddress("0xF2939afA86F6f933A3CE17fCAB007907B6b0B7a4"),
    sequencerFeedUrl: "wss://feed.testnet.chain.robinhood.com",
  }),
});
const MAX_UINT256 = (1n << 256n) - 1n;

function fail(field, message) {
  throw new Error(`${field} ${message}`);
}

function object(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(field, "must be an object");
  return value;
}

function integer(value, field) {
  if (!Number.isSafeInteger(value) || value <= 0) fail(field, "must be a positive safe integer");
  return value;
}

function quantity(value, field) {
  if (typeof value !== "string" || !/^[1-9][0-9]*$/.test(value)) {
    fail(field, "must be a positive integer string");
  }
  const parsed = BigInt(value);
  if (parsed > MAX_UINT256) fail(field, "exceeds uint256");
  return parsed;
}

function address(value, field, nullable = false) {
  if (value === null && nullable) return null;
  try {
    const parsed = getAddress(value);
    if (parsed === zeroAddress) fail(field, "must not be the zero address");
    return parsed;
  } catch (error) {
    if (error instanceof Error && error.message.startsWith(field)) throw error;
    fail(field, "must be a valid nonzero address");
  }
}

function bytes32(value, field, nullable = false) {
  if (value === null && nullable) return null;
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value)) {
    fail(field, "must be bytes32");
  }
  return value.toLowerCase();
}

function commit(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{40}$/.test(value) || /^0+$/.test(value)) {
    fail("source.commit", "must be a nonzero lowercase Git commit");
  }
  return value;
}

function transaction(value, field, nullable = false) {
  const hash = bytes32(value, field, nullable);
  if (hash && /^0x0+$/.test(hash)) fail(field, "must not be zero");
  return hash;
}

function runtimeCodeHash(value, field, nullable = false) {
  const hash = bytes32(value, field, nullable);
  if (hash && /^0x0+$/.test(hash)) fail(field, "must not be zero");
  return hash;
}

export function observerSetHash(observers, threshold) {
  return keccak256(encodeAbiParameters(
    [{ type: "address[]" }, { type: "uint8" }],
    [observers, threshold],
  ));
}

export function validateDeploymentManifest(raw, { requireDeployment = false } = {}) {
  const root = object(raw, "manifest");
  if (root.schemaVersion !== 1) fail("schemaVersion", "must equal 1");
  if (typeof root.name !== "string" || root.name.length === 0) fail("name", "is required");
  const source = object(root.source, "source");
  const chains = object(root.chains, "chains");
  const ethereum = object(chains.ethereum, "chains.ethereum");
  const robinhood = object(chains.robinhood, "chains.robinhood");
  const ethereumChainId = integer(ethereum.chainId, "chains.ethereum.chainId");
  const robinhoodChainId = integer(robinhood.chainId, "chains.robinhood.chainId");
  const pair = DEPLOYMENT_PAIRS[`${ethereumChainId}:${robinhoodChainId}`];
  if (!pair) fail("chains", "must select a supported Ethereum and Robinhood pair");

  const configuredInbox = address(ethereum.delayedInbox, "chains.ethereum.delayedInbox");
  if (configuredInbox !== pair.delayedInbox) fail("chains.ethereum.delayedInbox", "does not match the supported pair");
  if (robinhood.sequencerFeedUrl !== pair.sequencerFeedUrl) {
    fail("chains.robinhood.sequencerFeedUrl", "does not match the supported pair");
  }

  const configuration = object(root.configuration, "configuration");
  if (!Array.isArray(configuration.observers)) fail("configuration.observers", "must be an array");
  const observers = configuration.observers.map((value, index) =>
    address(value, `configuration.observers[${index}]`)
  );
  if (observers.length < 3 || observers.length > 16) {
    fail("configuration.observers", "must contain between 3 and 16 addresses");
  }
  for (let index = 1; index < observers.length; index += 1) {
    if (BigInt(observers[index]) <= BigInt(observers[index - 1])) {
      fail("configuration.observers", "must be unique and strictly increasing");
    }
  }
  const threshold = integer(configuration.threshold, "configuration.threshold");
  if (threshold <= Math.floor(observers.length / 2) || threshold > observers.length) {
    fail("configuration.threshold", "must be a strict majority of the observer set");
  }
  const calculatedObserverSetHash = observerSetHash(observers, threshold);
  const configuredObserverSetHash = bytes32(
    configuration.observerSetHash,
    "configuration.observerSetHash",
    !requireDeployment,
  );
  if (configuredObserverSetHash && configuredObserverSetHash !== calculatedObserverSetHash) {
    fail("configuration.observerSetHash", "does not match observers and threshold");
  }

  const contracts = object(root.contracts, "contracts");
  const reporter = object(contracts.reporter, "contracts.reporter");
  const feed = object(contracts.feed, "contracts.feed");
  const nullable = !requireDeployment;
  const services = object(root.services, "services");
  const pollIntervalMs = integer(services.pollIntervalMs, "services.pollIntervalMs");
  const backupDelayMs = integer(services.backupDelayMs, "services.backupDelayMs");
  if (pollIntervalMs !== 30_000) {
    fail("services.pollIntervalMs", "must equal the reviewed 30000 millisecond cadence");
  }
  if (backupDelayMs <= pollIntervalMs) {
    fail("services.backupDelayMs", "must exceed the primary polling interval");
  }

  const transactions = object(root.transactions, "transactions");
  const normalized = {
    schemaVersion: 1,
    name: root.name,
    source: {
      repository: String(source.repository ?? ""),
      commit: commit(source.commit),
    },
    chains: {
      ethereum: {
        chainId: ethereumChainId,
        deployer: address(ethereum.deployer, "chains.ethereum.deployer"),
        minimumDeployerBalanceWei: quantity(
          ethereum.minimumDeployerBalanceWei,
          "chains.ethereum.minimumDeployerBalanceWei",
        ),
        delayedInbox: configuredInbox,
        explorer: String(ethereum.explorer ?? ""),
      },
      robinhood: {
        chainId: robinhoodChainId,
        deployer: address(robinhood.deployer, "chains.robinhood.deployer"),
        minimumDeployerBalanceWei: quantity(
          robinhood.minimumDeployerBalanceWei,
          "chains.robinhood.minimumDeployerBalanceWei",
        ),
        sequencerFeedUrl: robinhood.sequencerFeedUrl,
        explorer: String(robinhood.explorer ?? ""),
      },
    },
    contracts: {
      reporter: {
        address: address(reporter.address, "contracts.reporter.address", nullable),
        deploymentTransaction: transaction(
          reporter.deploymentTransaction,
          "contracts.reporter.deploymentTransaction",
          nullable,
        ),
        runtimeCodeHash: runtimeCodeHash(
          reporter.runtimeCodeHash,
          "contracts.reporter.runtimeCodeHash",
          nullable,
        ),
      },
      feed: {
        address: address(feed.address, "contracts.feed.address", nullable),
        deploymentTransaction: transaction(
          feed.deploymentTransaction,
          "contracts.feed.deploymentTransaction",
          nullable,
        ),
        runtimeCodeHash: runtimeCodeHash(
          feed.runtimeCodeHash,
          "contracts.feed.runtimeCodeHash",
          nullable,
        ),
      },
    },
    configuration: {
      owner: address(configuration.owner, "configuration.owner"),
      refundAddress: address(configuration.refundAddress, "configuration.refundAddress"),
      observers,
      threshold,
      observerSetHash: configuredObserverSetHash,
      calculatedObserverSetHash,
      statusGasLimit: quantity(configuration.statusGasLimit, "configuration.statusGasLimit"),
      configurationGasLimit: quantity(
        configuration.configurationGasLimit,
        "configuration.configurationGasLimit",
      ),
      gasPriceBid: quantity(configuration.gasPriceBid, "configuration.gasPriceBid"),
      reserveMessages: integer(configuration.reserveMessages, "configuration.reserveMessages"),
    },
    transactions: {
      funding: transaction(transactions.funding, "transactions.funding", true),
      initialization: transaction(
        transactions.initialization,
        "transactions.initialization",
        nullable,
      ),
    },
    services: { pollIntervalMs, backupDelayMs },
  };
  if (!normalized.source.repository.startsWith("https://")) {
    fail("source.repository", "must be an HTTPS URL");
  }
  if (normalized.configuration.reserveMessages < 4) {
    fail("configuration.reserveMessages", "must be at least 4");
  }
  return normalized;
}

export function validateHealthySnapshot(
  snapshot,
  manifest,
  now,
  { minimumLeaseRemaining = 600n } = {},
) {
  const expected = manifest.configuration;
  const fields = [
    [snapshot.reporter.owner, expected.owner, "reporter owner"],
    [snapshot.reporter.inbox, manifest.chains.ethereum.delayedInbox, "reporter inbox"],
    [snapshot.reporter.childChainId, BigInt(manifest.chains.robinhood.chainId), "child chain"],
    [snapshot.reporter.l2Feed, manifest.contracts.feed.address, "reporter L2 feed"],
    [snapshot.reporter.refundAddress, expected.refundAddress, "refund address"],
    [snapshot.reporter.statusGasLimit, expected.statusGasLimit, "status gas limit"],
    [snapshot.reporter.configurationGasLimit, expected.configurationGasLimit, "configuration gas limit"],
    [snapshot.reporter.gasPriceBid, expected.gasPriceBid, "gas price bid"],
    [snapshot.feed.l1Reporter, manifest.contracts.reporter.address, "feed L1 reporter"],
    [snapshot.reporter.threshold, expected.threshold, "reporter threshold"],
    [snapshot.feed.threshold, expected.threshold, "feed threshold"],
  ];
  for (const [actual, wanted, field] of fields) {
    if (actual !== wanted) throw new Error(`${field} mismatch`);
  }
  const expectedObservers = expected.observers.join(",");
  if (snapshot.reporter.observers.join(",") !== expectedObservers) throw new Error("reporter observer set mismatch");
  if (snapshot.feed.observers.join(",") !== expectedObservers) throw new Error("feed observer set mismatch");
  if (snapshot.reporter.observerSetVersion === 0n) throw new Error("observer set is not initialized");
  if (snapshot.reporter.observerSetVersion !== snapshot.feed.observerSetVersion) {
    throw new Error("L1 and L2 observer set versions differ");
  }
  if (snapshot.reporter.statusSequence !== snapshot.feed.statusSequence) {
    throw new Error("L1 and L2 status sequences differ");
  }
  if (!snapshot.reporter.healthy) throw new Error("L1 reporter is impaired");
  if (snapshot.feed.lastHeartbeatStatusSequence !== snapshot.feed.statusSequence) {
    throw new Error("heartbeat belongs to another status sequence");
  }
  if (snapshot.feed.availabilityReason !== 1) throw new Error("L2 feed is not healthy");
  if (snapshot.feed.answer !== 0n) throw new Error("latestRoundData does not report healthy");
  if (snapshot.feed.healthyUntil <= now + minimumLeaseRemaining) {
    throw new Error(`heartbeat has ${minimumLeaseRemaining} seconds or less remaining`);
  }
  const maximumQuote = snapshot.reporter.statusQuote > snapshot.reporter.configurationQuote
    ? snapshot.reporter.statusQuote
    : snapshot.reporter.configurationQuote;
  const requiredBalance = maximumQuote * BigInt(expected.reserveMessages);
  if (snapshot.reporter.balance < requiredBalance) throw new Error("reporter retryable reserve is underfunded");
  return { requiredBalance, leaseRemaining: snapshot.feed.healthyUntil - now };
}
