import {
  createPublicClient,
  createWalletClient,
  defineChain,
  getAddress,
  http,
  recoverTypedDataAddress,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import {
  feedAbi,
  heartbeatDomain,
  heartbeatTypes,
  reporterAbi,
  statusReportDomain,
  statusReportTypes,
} from "./abi.mjs";
import { recoverAuthorizedSignatures } from "./quorum.mjs";
import { assertRpcChain, getBlock, readSequencerFeedHead, waitForBlock } from "./rpc.mjs";
import {
  LEASE_SECONDS,
  ObserverState,
  POLL_INTERVAL_MS,
  STATUS_VALIDITY_SECONDS,
  heartbeatDue,
  normalizeHeartbeat,
  normalizeStatusReport,
  parsePrivateKey,
  requireEnv,
  serializeBigInts,
  validateHeartbeat,
} from "./shared.mjs";

const feedAddress = getAddress(requireEnv("SEQUENCER_SIGNAL_FEED"));
const reporterAddress = getAddress(requireEnv("SEQUENCER_L1_REPORTER"));
const directFeedUrl = requireEnv("DIRECT_SEQUENCER_FEED_URL");
const robinhoodRpcUrl = requireEnv("ROBINHOOD_RPC_URL");
const ethereumRpcUrl = requireEnv("ETHEREUM_RPC_URL");
const observerUrls = requireEnv("OBSERVER_URLS").split(",").map((value) => value.trim());
const l1Account = privateKeyToAccount(parsePrivateKey("L1_RELAYER_PRIVATE_KEY"));
const l2Account = privateKeyToAccount(parsePrivateKey("L2_RELAYER_PRIVATE_KEY"));
const robinhoodChainId = Number(process.env.ROBINHOOD_CHAIN_ID ?? "4663");
const ethereumChainId = Number(process.env.ETHEREUM_CHAIN_ID ?? "1");
const pollInterval = Number(process.env.POLL_INTERVAL_MS ?? String(POLL_INTERVAL_MS));
const runOnce = process.env.RUN_ONCE === "true";
const relayerRole = process.env.RELAYER_ROLE ?? "primary";
const backupDelay = Number(process.env.BACKUP_DELAY_MS ?? "45000");
if (!["primary", "backup"].includes(relayerRole)) throw new Error("RELAYER_ROLE must be primary or backup");
if (!Number.isFinite(pollInterval) || pollInterval <= 0) throw new Error("POLL_INTERVAL_MS must be positive");
if (!Number.isFinite(backupDelay) || backupDelay < 0) throw new Error("BACKUP_DELAY_MS must not be negative");

const robinhoodChain = defineChain({
  id: robinhoodChainId,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [robinhoodRpcUrl] } },
});
const ethereumChain = defineChain({
  id: ethereumChainId,
  name: "Ethereum",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [ethereumRpcUrl] } },
});
const l2Public = createPublicClient({ chain: robinhoodChain, transport: http() });
const l2Wallet = createWalletClient({ account: l2Account, chain: robinhoodChain, transport: http() });
const l1Public = createPublicClient({ chain: ethereumChain, transport: http() });
const l1Wallet = createWalletClient({ account: l1Account, chain: ethereumChain, transport: http() });

async function requestJson(url, path, body) {
  const response = await fetch(new URL(path, url), {
    method: body ? "POST" : "GET",
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(12_000),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error ?? `observer HTTP ${response.status}`);
  return payload;
}

async function observerConsensus(threshold) {
  const settled = await Promise.allSettled(observerUrls.map((url) => requestJson(url, "/health")));
  const counts = new Map([[ObserverState.HEALTHY, 0], [ObserverState.IMPAIRED, 0]]);
  for (const result of settled) {
    if (result.status === "fulfilled" && counts.has(result.value.state)) {
      counts.set(result.value.state, counts.get(result.value.state) + 1);
    }
  }
  if (counts.get(ObserverState.HEALTHY) >= threshold) return ObserverState.HEALTHY;
  if (counts.get(ObserverState.IMPAIRED) >= threshold) return ObserverState.IMPAIRED;
  return ObserverState.UNKNOWN;
}

async function collectSignatures({ path, field, value, observers, domain, types, primaryType }) {
  const settled = await Promise.allSettled(
    observerUrls.map((url) => requestJson(url, path, { [field]: serializeBigInts(value) })),
  );
  return await recoverAuthorizedSignatures({
    settled,
    authorizedObservers: observers,
    recover: async (signature) => await recoverTypedDataAddress({
      domain,
      types,
      primaryType,
      message: value,
      signature,
    }),
  });
}

async function maybeDelayBackup() {
  if (relayerRole === "backup") await new Promise((resolve) => setTimeout(resolve, backupDelay));
}

async function reconcileStatus() {
  const [version, sequence, currentHealthy, threshold, observers] = await Promise.all([
    l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "observerSetVersion" }),
    l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "statusSequence" }),
    l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "healthy" }),
    l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "threshold" }),
    l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "observers" }),
  ]);
  const consensus = await observerConsensus(Number(threshold));
  if (consensus === ObserverState.UNKNOWN) throw new Error("observer status quorum is unavailable");
  const desiredHealthy = consensus === ObserverState.HEALTHY;
  if (desiredHealthy === currentHealthy) return desiredHealthy;

  const now = BigInt(Math.floor(Date.now() / 1_000));
  const report = normalizeStatusReport({
    observerSetVersion: version,
    sequence: sequence + 1n,
    healthy: desiredHealthy,
    observedAt: now,
    validUntil: now + STATUS_VALIDITY_SECONDS,
  });
  const quorum = await collectSignatures({
    path: "/status",
    field: "report",
    value: report,
    observers,
    domain: statusReportDomain(reporterAddress, ethereumChainId),
    types: statusReportTypes,
    primaryType: "StatusReport",
  });
  if (quorum.length < threshold) throw new Error(`status quorum unavailable: ${quorum.length}/${threshold}`);
  await maybeDelayBackup();
  const latestSequence = await l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "statusSequence" });
  if (latestSequence !== sequence) return desiredHealthy;
  const args = [report, quorum.map((entry) => entry.signature)];
  const { request } = await l1Public.simulateContract({
    account: l1Account,
    address: reporterAddress,
    abi: reporterAbi,
    functionName: "submitStatusReport",
    args,
  });
  const hash = await l1Wallet.writeContract(request);
  await l1Public.waitForTransactionReceipt({ hash });
  process.stdout.write(`submitted L1 status ${desiredHealthy ? "HEALTHY" : "IMPAIRED"}: ${hash}\n`);
  return desiredHealthy;
}

async function renewHeartbeat() {
  const [version, statusSequence, lastBlock, healthyUntil, threshold, observers, directHead] =
    await Promise.all([
      l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "observerSetVersion" }),
      l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "statusSequence" }),
      l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "lastObservedBlockNumber" }),
      l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "healthyUntil" }),
      l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "threshold" }),
      l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "observers" }),
      readSequencerFeedHead(directFeedUrl),
    ]);
  const now = BigInt(Math.floor(Date.now() / 1_000));
  if (!heartbeatDue(healthyUntil, now)) return;
  if (directHead.number === 0n) throw new Error("sequencer feed returned genesis");
  const targetBlock = directHead.number - 1n;
  if (targetBlock <= lastBlock) throw new Error("no newer mutually observable block");
  const [directReferenceBlock, referenceBlock] = await Promise.all([
    waitForBlock(robinhoodRpcUrl, directHead.number),
    waitForBlock(robinhoodRpcUrl, targetBlock),
  ]);
  const referenceHead = await getBlock(robinhoodRpcUrl);
  const heartbeat = normalizeHeartbeat({
    observerSetVersion: version,
    statusSequence,
    observedBlockNumber: targetBlock,
    observedBlockHash: referenceBlock.hash,
    validUntil: now + LEASE_SECONDS,
  });
  validateHeartbeat({
    heartbeat,
    expectedObserverSetVersion: version,
    expectedStatusSequence: statusSequence,
    directHead,
    referenceHead,
    directReferenceBlock,
    referenceBlock,
    now,
  });
  const quorum = await collectSignatures({
    path: "/heartbeat",
    field: "heartbeat",
    value: heartbeat,
    observers,
    domain: heartbeatDomain(feedAddress, robinhoodChainId),
    types: heartbeatTypes,
    primaryType: "Heartbeat",
  });
  if (quorum.length < threshold) throw new Error(`heartbeat quorum unavailable: ${quorum.length}/${threshold}`);
  await maybeDelayBackup();
  const latestUntil = await l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "healthyUntil" });
  if (latestUntil > healthyUntil) return;
  const args = [heartbeat, quorum.map((entry) => entry.signature)];
  const { request } = await l2Public.simulateContract({
    account: l2Account,
    address: feedAddress,
    abi: feedAbi,
    functionName: "submitHeartbeat",
    args,
  });
  const hash = await l2Wallet.writeContract(request);
  await l2Public.waitForTransactionReceipt({ hash });
  process.stdout.write(`renewed L2 heartbeat through ${heartbeat.validUntil}: ${hash}\n`);
}

async function runRound() {
  const healthy = await reconcileStatus();
  if (healthy) await renewHeartbeat();
}

const [, , , configuredChildChainId, configuredFeed, configuredReporter] = await Promise.all([
  assertRpcChain(robinhoodRpcUrl, robinhoodChainId),
  assertRpcChain(ethereumRpcUrl, ethereumChainId),
  readSequencerFeedHead(directFeedUrl),
  l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "childChainId" }),
  l1Public.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "l2Feed" }),
  l2Public.readContract({ address: feedAddress, abi: feedAbi, functionName: "l1Reporter" }),
]);
if (configuredChildChainId !== BigInt(robinhoodChainId)) throw new Error("reporter child chain mismatch");
if (getAddress(configuredFeed) !== feedAddress) throw new Error("reporter L2 feed mismatch");
if (getAddress(configuredReporter) !== reporterAddress) throw new Error("feed L1 reporter mismatch");

do {
  try {
    await runRound();
  } catch (error) {
    process.stderr.write(`${new Date().toISOString()} round failed: ${error instanceof Error ? error.message : "unknown error"}\n`);
  }
  if (!runOnce) await new Promise((resolve) => setTimeout(resolve, pollInterval));
} while (!runOnce);
