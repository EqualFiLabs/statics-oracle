import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import {
  createPublicClient,
  defineChain,
  getAddress,
  http,
  keccak256,
  zeroAddress,
} from "viem";

import { reporterAbi, feedAbi } from "./abi.mjs";
import { parseObserverAuthTokens } from "./auth.mjs";
import { validateDeploymentManifest, validateHealthySnapshot } from "./deployment.mjs";
import { getBlock, readSequencerFeedHead, waitForBlock } from "./rpc.mjs";
import { requireEnv, serializeBigInts, validateObservedHeads } from "./shared.mjs";

const mode = process.argv[2];

function reportFailure(error) {
  process.stderr.write(`${JSON.stringify({
    mode: mode ?? "unknown",
    ok: false,
    error: error instanceof Error ? error.message : "deployment check failed",
  })}\n`);
}

if (!new Set(["preflight", "smoke", "monitor"]).has(mode)) {
  reportFailure(new Error("usage: node src/deployment-check.mjs <preflight|smoke|monitor>"));
  process.exit(1);
}

let manifest;
let ethereumRpcUrl;
let robinhoodRpcUrl;
let l1;
let l2;
try {
  const manifestPath = requireEnv("SEQUENCER_DEPLOYMENT_MANIFEST");
  const rawManifest = JSON.parse(await readFile(manifestPath, "utf8"));
  manifest = validateDeploymentManifest(rawManifest, { requireDeployment: mode !== "preflight" });
  ethereumRpcUrl = requireEnv("ETHEREUM_RPC_URL");
  robinhoodRpcUrl = requireEnv("ROBINHOOD_RPC_URL");
  const ethereumChain = defineChain({
    id: manifest.chains.ethereum.chainId,
    name: "Ethereum Parent",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [ethereumRpcUrl] } },
  });
  const robinhoodChain = defineChain({
    id: manifest.chains.robinhood.chainId,
    name: "Robinhood Child",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [robinhoodRpcUrl] } },
  });
  l1 = createPublicClient({ chain: ethereumChain, transport: http() });
  l2 = createPublicClient({ chain: robinhoodChain, transport: http() });
} catch (error) {
  reportFailure(error);
  process.exit(1);
}

function assertEqual(actual, expected, field) {
  if (actual !== expected) throw new Error(`${field} mismatch`);
}

function assertBytecode(value, field) {
  if (!value || value === "0x") throw new Error(`${field} has no bytecode`);
  return value;
}

async function assertNetworkAndFeed() {
  const [l1ChainId, l2ChainId, inboxCode, directHead] = await Promise.all([
    l1.getChainId(),
    l2.getChainId(),
    l1.getBytecode({ address: manifest.chains.ethereum.delayedInbox }),
    readSequencerFeedHead(manifest.chains.robinhood.sequencerFeedUrl),
  ]);
  assertEqual(l1ChainId, manifest.chains.ethereum.chainId, "Ethereum chain ID");
  assertEqual(l2ChainId, manifest.chains.robinhood.chainId, "Robinhood chain ID");
  assertBytecode(inboxCode, "delayed inbox");
  const [directReferenceBlock, referenceHead] = await Promise.all([
    waitForBlock(robinhoodRpcUrl, directHead.number),
    getBlock(robinhoodRpcUrl),
  ]);
  validateObservedHeads({
    directHead,
    directReferenceBlock,
    referenceHead,
    now: BigInt(Math.floor(Date.now() / 1_000)),
  });
  return { directHead, referenceHead };
}

function currentCommit() {
  const repository = fileURLToPath(new URL("../..", import.meta.url));
  try {
    execFileSync("git", ["diff", "--quiet"], { cwd: repository, stdio: "ignore" });
    execFileSync("git", ["diff", "--cached", "--quiet"], { cwd: repository, stdio: "ignore" });
  } catch {
    throw new Error("tracked checkout is dirty");
  }
  return execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: repository,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

async function preflight() {
  assertEqual(currentCommit(), manifest.source.commit, "source commit");
  const [network, l1Balance, l2Balance, contracts] = await Promise.all([
    assertNetworkAndFeed(),
    l1.getBalance({ address: manifest.chains.ethereum.deployer }),
    l2.getBalance({ address: manifest.chains.robinhood.deployer }),
    preflightContracts(),
  ]);
  if (l1Balance < manifest.chains.ethereum.minimumDeployerBalanceWei) {
    throw new Error("Ethereum deployer balance is below the manifest minimum");
  }
  if (l2Balance < manifest.chains.robinhood.minimumDeployerBalanceWei) {
    throw new Error("Robinhood deployer balance is below the manifest minimum");
  }
  return {
    mode,
    manifest: manifest.name,
    sourceCommit: manifest.source.commit,
    observerSetHash: manifest.configuration.calculatedObserverSetHash,
    contracts,
    ethereum: {
      chainId: manifest.chains.ethereum.chainId,
      deployer: manifest.chains.ethereum.deployer,
      balance: l1Balance,
      minimumBalance: manifest.chains.ethereum.minimumDeployerBalanceWei,
    },
    robinhood: {
      chainId: manifest.chains.robinhood.chainId,
      deployer: manifest.chains.robinhood.deployer,
      balance: l2Balance,
      minimumBalance: manifest.chains.robinhood.minimumDeployerBalanceWei,
      directHead: network.directHead.number,
      referenceHead: network.referenceHead.number,
    },
  };
}

async function preflightContracts() {
  const reporter = manifest.contracts.reporter;
  const feed = manifest.contracts.feed;
  if (!reporter.address && !feed.address) return { deployed: false };
  if (!reporter.address || !feed.address) {
    throw new Error("reporter and feed addresses must be supplied together");
  }
  const [
    reporterCode,
    feedCode,
    owner,
    inbox,
    childChainId,
    l2Feed,
    refundAddress,
    statusGasLimit,
    configurationGasLimit,
    gasPriceBid,
    threshold,
    observers,
    statusQuote,
    configurationQuote,
    reporterBalance,
    l1Reporter,
  ] = await Promise.all([
    l1.getBytecode({ address: reporter.address }),
    l2.getBytecode({ address: feed.address }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "owner" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "inbox" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "childChainId" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "l2Feed" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "l2RefundAddress" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "statusGasLimit" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "configurationGasLimit" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "gasPriceBid" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "threshold" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "observers" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "quoteStatusRetryable" }),
    l1.readContract({ address: reporter.address, abi: reporterAbi, functionName: "quoteConfigurationRetryable" }),
    l1.getBalance({ address: reporter.address }),
    l2.readContract({ address: feed.address, abi: feedAbi, functionName: "l1Reporter" }),
  ]);
  const actualReporterCodeHash = keccak256(assertBytecode(reporterCode, "reporter"));
  const actualFeedCodeHash = keccak256(assertBytecode(feedCode, "feed"));
  const expected = manifest.configuration;
  assertEqual(getAddress(owner), expected.owner, "reporter owner");
  assertEqual(getAddress(inbox), manifest.chains.ethereum.delayedInbox, "reporter inbox");
  assertEqual(childChainId, BigInt(manifest.chains.robinhood.chainId), "reporter child chain");
  assertEqual(getAddress(l2Feed), zeroAddress, "reporter pre-initialization L2 feed");
  assertEqual(getAddress(refundAddress), expected.refundAddress, "reporter refund address");
  assertEqual(statusGasLimit, expected.statusGasLimit, "status gas limit");
  assertEqual(configurationGasLimit, expected.configurationGasLimit, "configuration gas limit");
  assertEqual(gasPriceBid, expected.gasPriceBid, "gas price bid");
  assertEqual(Number(threshold), expected.threshold, "reporter threshold");
  assertEqual(
    observers.map((value) => getAddress(value)).join(","),
    expected.observers.join(","),
    "reporter observers",
  );
  assertEqual(getAddress(l1Reporter), reporter.address, "feed L1 reporter");
  if (reporter.runtimeCodeHash) {
    assertEqual(actualReporterCodeHash, reporter.runtimeCodeHash, "reporter runtime code hash");
  }
  if (feed.runtimeCodeHash) {
    assertEqual(actualFeedCodeHash, feed.runtimeCodeHash, "feed runtime code hash");
  }
  const maximumQuote = statusQuote > configurationQuote ? statusQuote : configurationQuote;
  const requiredPreInitializationBalance =
    configurationQuote + maximumQuote * BigInt(expected.reserveMessages);
  return {
    deployed: true,
    reporter: reporter.address,
    feed: feed.address,
    reporterRuntimeCodeHash: actualReporterCodeHash,
    feedRuntimeCodeHash: actualFeedCodeHash,
    reporterBalance,
    requiredPreInitializationBalance,
    fundingShortfall: reporterBalance >= requiredPreInitializationBalance
      ? 0n
      : requiredPreInitializationBalance - reporterBalance,
  };
}

async function assertSuccessfulTransaction(client, hash, expectedContract, field) {
  const receipt = await client.getTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${field} transaction reverted`);
  if (expectedContract && getAddress(receipt.contractAddress) !== expectedContract) {
    throw new Error(`${field} deployed an unexpected contract address`);
  }
  return receipt.blockNumber;
}

async function observerHealth() {
  const urls = requireEnv("OBSERVER_URLS").split(",").map((value) => value.trim());
  const tokens = parseObserverAuthTokens(requireEnv("OBSERVER_AUTH_TOKENS"), urls.length);
  if (urls.length !== manifest.configuration.observers.length) {
    throw new Error("observer endpoint count does not match the manifest");
  }
  const results = await Promise.all(urls.map(async (url, index) => {
    const response = await fetch(new URL("/health", url), {
      headers: { authorization: `Bearer ${tokens[index]}` },
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) throw new Error(`observer ${index + 1} returned HTTP ${response.status}`);
    const payload = await response.json();
    if (payload.state !== "HEALTHY") throw new Error(`observer ${index + 1} is ${payload.state}`);
    if (payload.configuration?.ethereumChainId !== manifest.chains.ethereum.chainId) {
      throw new Error(`observer ${index + 1} Ethereum chain mismatch`);
    }
    if (payload.configuration?.robinhoodChainId !== manifest.chains.robinhood.chainId) {
      throw new Error(`observer ${index + 1} Robinhood chain mismatch`);
    }
    if (getAddress(payload.configuration?.reporter) !== manifest.contracts.reporter.address) {
      throw new Error(`observer ${index + 1} reporter mismatch`);
    }
    if (getAddress(payload.configuration?.feed) !== manifest.contracts.feed.address) {
      throw new Error(`observer ${index + 1} feed mismatch`);
    }
    if (payload.configuration?.pollIntervalMs !== manifest.services.pollIntervalMs) {
      throw new Error(`observer ${index + 1} polling interval mismatch`);
    }
    return getAddress(payload.observer);
  }));
  const actual = [...results].sort((left, right) => BigInt(left) < BigInt(right) ? -1 : 1);
  if (actual.join(",") !== manifest.configuration.observers.join(",")) {
    throw new Error("observer endpoints do not match the manifest signer set");
  }
  return results;
}

async function deployedState() {
  const reporter = manifest.contracts.reporter.address;
  const feed = manifest.contracts.feed.address;
  const [
    owner,
    inbox,
    childChainId,
    l2Feed,
    refundAddress,
    statusGasLimit,
    configurationGasLimit,
    gasPriceBid,
    reporterThreshold,
    reporterObservers,
    reporterVersion,
    reporterSequence,
    reporterHealthy,
    statusQuote,
    configurationQuote,
    reporterBalance,
    l1Reporter,
    feedThreshold,
    feedObservers,
    feedVersion,
    feedSequence,
    heartbeatSequence,
    healthyUntil,
    availabilityReason,
    roundData,
  ] = await Promise.all([
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "owner" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "inbox" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "childChainId" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "l2Feed" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "l2RefundAddress" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "statusGasLimit" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "configurationGasLimit" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "gasPriceBid" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "threshold" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "observers" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "observerSetVersion" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "statusSequence" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "healthy" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "quoteStatusRetryable" }),
    l1.readContract({ address: reporter, abi: reporterAbi, functionName: "quoteConfigurationRetryable" }),
    l1.getBalance({ address: reporter }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "l1Reporter" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "threshold" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "observers" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "observerSetVersion" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "statusSequence" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "lastHeartbeatStatusSequence" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "healthyUntil" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "availabilityReason" }),
    l2.readContract({ address: feed, abi: feedAbi, functionName: "latestRoundData" }),
  ]);
  return {
    reporter: {
      owner: getAddress(owner),
      inbox: getAddress(inbox),
      childChainId,
      l2Feed: getAddress(l2Feed),
      refundAddress: getAddress(refundAddress),
      statusGasLimit,
      configurationGasLimit,
      gasPriceBid,
      threshold: Number(reporterThreshold),
      observers: reporterObservers.map((value) => getAddress(value)),
      observerSetVersion: reporterVersion,
      statusSequence: reporterSequence,
      healthy: reporterHealthy,
      statusQuote,
      configurationQuote,
      balance: reporterBalance,
    },
    feed: {
      l1Reporter: getAddress(l1Reporter),
      threshold: Number(feedThreshold),
      observers: feedObservers.map((value) => getAddress(value)),
      observerSetVersion: feedVersion,
      statusSequence: feedSequence,
      lastHeartbeatStatusSequence: heartbeatSequence,
      healthyUntil,
      availabilityReason: Number(availabilityReason),
      answer: roundData[1],
    },
  };
}

async function smoke() {
  const reporter = manifest.contracts.reporter;
  const feed = manifest.contracts.feed;
  const [network, reporterCode, feedCode, reporterBlock, feedBlock, initializationBlock, observers] =
    await Promise.all([
      assertNetworkAndFeed(),
      l1.getBytecode({ address: reporter.address }),
      l2.getBytecode({ address: feed.address }),
      assertSuccessfulTransaction(l1, reporter.deploymentTransaction, reporter.address, "reporter deployment"),
      assertSuccessfulTransaction(l2, feed.deploymentTransaction, feed.address, "feed deployment"),
      assertSuccessfulTransaction(l1, manifest.transactions.initialization, null, "initialization"),
      observerHealth(),
    ]);
  assertEqual(keccak256(assertBytecode(reporterCode, "reporter")), reporter.runtimeCodeHash, "reporter runtime code hash");
  assertEqual(keccak256(assertBytecode(feedCode, "feed")), feed.runtimeCodeHash, "feed runtime code hash");
  if (manifest.transactions.funding) {
    await assertSuccessfulTransaction(l1, manifest.transactions.funding, null, "funding");
  }
  const snapshot = await deployedState();
  const minimumLeaseRemaining = mode === "monitor" ? 300n : 600n;
  const health = validateHealthySnapshot(
    snapshot,
    manifest,
    BigInt(Math.floor(Date.now() / 1_000)),
    { minimumLeaseRemaining },
  );
  return {
    mode,
    manifest: manifest.name,
    sourceCommit: manifest.source.commit,
    observerSetHash: manifest.configuration.observerSetHash,
    blocks: { reporterDeployment: reporterBlock, feedDeployment: feedBlock, initialization: initializationBlock },
    chainHeads: { direct: network.directHead.number, reference: network.referenceHead.number },
    observerCount: observers.length,
    observerSetVersion: snapshot.reporter.observerSetVersion,
    statusSequence: snapshot.reporter.statusSequence,
    reporterBalance: snapshot.reporter.balance,
    requiredReporterBalance: health.requiredBalance,
    leaseRemaining: health.leaseRemaining,
    leaseWarning: health.leaseRemaining <= 600n,
    availabilityAnswer: snapshot.feed.answer,
  };
}

try {
  const result = mode === "preflight" ? await preflight() : await smoke();
  process.stdout.write(`${JSON.stringify(serializeBigInts(result), null, 2)}\n`);
} catch (error) {
  reportFailure(error);
  process.exitCode = 1;
}
