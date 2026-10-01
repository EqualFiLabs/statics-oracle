import { createServer } from "node:http";
import { createPublicClient, defineChain, getAddress, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";

import {
  feedAbi,
  heartbeatDomain,
  heartbeatTypes,
  reporterAbi,
  statusReportDomain,
  statusReportTypes,
} from "./abi.mjs";
import { assertRpcChain, getBlock, readSequencerFeedHead, waitForBlock } from "./rpc.mjs";
import {
  AvailabilityTracker,
  ObserverState,
  POLL_INTERVAL_MS,
  normalizeHeartbeat,
  normalizeStatusReport,
  parsePrivateKey,
  requireEnv,
  serializeBigInts,
  validateCrossChainState,
  validateHeartbeat,
  validateObservedHeads,
  validateStatusReport,
} from "./shared.mjs";

const feedAddress = getAddress(requireEnv("SEQUENCER_SIGNAL_FEED"));
const reporterAddress = getAddress(requireEnv("SEQUENCER_L1_REPORTER"));
const directFeedUrl = requireEnv("DIRECT_SEQUENCER_FEED_URL");
const robinhoodRpcUrl = requireEnv("ROBINHOOD_RPC_URL");
const ethereumRpcUrl = requireEnv("ETHEREUM_RPC_URL");
const robinhoodChainId = Number(process.env.ROBINHOOD_CHAIN_ID ?? "4663");
const ethereumChainId = Number(process.env.ETHEREUM_CHAIN_ID ?? "1");
const account = privateKeyToAccount(parsePrivateKey("OBSERVER_PRIVATE_KEY"));
const host = process.env.OBSERVER_HOST ?? "127.0.0.1";
const port = Number(process.env.OBSERVER_PORT ?? "8787");
const pollInterval = Number(process.env.POLL_INTERVAL_MS ?? String(POLL_INTERVAL_MS));
if (!Number.isInteger(port) || port < 1 || port > 65_535) throw new Error("OBSERVER_PORT is invalid");
if (!Number.isFinite(pollInterval) || pollInterval <= 0) throw new Error("POLL_INTERVAL_MS must be positive");
const tracker = new AvailabilityTracker();
let lastSample;
let lastSignedStatusSequence = -1n;
let lastSignedStatusHealthy;
let lastSignedBlock = -1n;
let lastSignedHash;

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
const l2Client = createPublicClient({ chain: robinhoodChain, transport: http() });
const l1Client = createPublicClient({ chain: ethereumChain, transport: http() });

async function readJson(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > 8_192) throw new Error("request body is too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function respond(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

async function sampleAvailability() {
  try {
    const directHead = await readSequencerFeedHead(directFeedUrl);
    const directReferenceBlock = await waitForBlock(robinhoodRpcUrl, directHead.number);
    const referenceHead = await getBlock(robinhoodRpcUrl);
    const now = BigInt(Math.floor(Date.now() / 1_000));
    validateObservedHeads({ directHead, referenceHead, directReferenceBlock, now });
    lastSample = { directHead, directReferenceBlock, referenceHead };
    tracker.record(true);
  } catch (error) {
    tracker.record(false, Date.now(), error);
  }
}

async function signHeartbeat(rawHeartbeat) {
  if (tracker.state !== ObserverState.HEALTHY || !lastSample) throw new Error("observer is not healthy");
  const heartbeat = normalizeHeartbeat(rawHeartbeat);
  const [version, statusSequence, lastBlock, authorized, l1Version, l1StatusSequence] =
    await Promise.all([
      l2Client.readContract({ address: feedAddress, abi: feedAbi, functionName: "observerSetVersion" }),
      l2Client.readContract({ address: feedAddress, abi: feedAbi, functionName: "statusSequence" }),
      l2Client.readContract({ address: feedAddress, abi: feedAbi, functionName: "lastObservedBlockNumber" }),
      l2Client.readContract({
        address: feedAddress,
        abi: feedAbi,
        functionName: "isObserver",
        args: [account.address],
      }),
      l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "observerSetVersion" }),
      l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "statusSequence" }),
    ]);
  if (!authorized) throw new Error("signing key is not in the L2 observer set");
  validateCrossChainState({
    l1ObserverSetVersion: l1Version,
    l1StatusSequence,
    l2ObserverSetVersion: version,
    l2StatusSequence: statusSequence,
  });
  if (heartbeat.observedBlockNumber <= lastBlock || heartbeat.observedBlockNumber < lastSignedBlock) {
    throw new Error("proposed block is not newer");
  }
  if (heartbeat.observedBlockNumber === lastSignedBlock && heartbeat.observedBlockHash !== lastSignedHash) {
    throw new Error("refusing a conflicting block");
  }
  const referenceBlock = await getBlock(robinhoodRpcUrl, heartbeat.observedBlockNumber);
  validateHeartbeat({
    heartbeat,
    expectedObserverSetVersion: version,
    expectedStatusSequence: statusSequence,
    ...lastSample,
    referenceBlock,
    now: BigInt(Math.floor(Date.now() / 1_000)),
  });
  const signature = await account.signTypedData({
    domain: heartbeatDomain(feedAddress, robinhoodChainId),
    types: heartbeatTypes,
    primaryType: "Heartbeat",
    message: heartbeat,
  });
  lastSignedBlock = heartbeat.observedBlockNumber;
  lastSignedHash = heartbeat.observedBlockHash;
  return { observer: account.address, heartbeat: serializeBigInts(heartbeat), signature };
}

async function signStatus(rawReport) {
  const report = normalizeStatusReport(rawReport);
  const [version, sequence, currentHealthy, authorized] = await Promise.all([
    l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "observerSetVersion" }),
    l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "statusSequence" }),
    l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "healthy" }),
    l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "isObserver", args: [account.address] }),
  ]);
  if (!authorized) throw new Error("signing key is not in the L1 observer set");
  validateStatusReport({
    report,
    version,
    sequence,
    currentHealthy,
    localState: tracker.state,
    now: BigInt(Math.floor(Date.now() / 1_000)),
  });
  if (report.sequence < lastSignedStatusSequence) throw new Error("status sequence regressed");
  if (report.sequence === lastSignedStatusSequence && report.healthy !== lastSignedStatusHealthy) {
    throw new Error("refusing a conflicting status report");
  }
  const signature = await account.signTypedData({
    domain: statusReportDomain(reporterAddress, ethereumChainId),
    types: statusReportTypes,
    primaryType: "StatusReport",
    message: report,
  });
  lastSignedStatusSequence = report.sequence;
  lastSignedStatusHealthy = report.healthy;
  return { observer: account.address, report: serializeBigInts(report), signature };
}

const [, , configuredChildChainId, configuredFeed, configuredReporter] = await Promise.all([
  assertRpcChain(robinhoodRpcUrl, robinhoodChainId),
  assertRpcChain(ethereumRpcUrl, ethereumChainId),
  l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "childChainId" }),
  l1Client.readContract({ address: reporterAddress, abi: reporterAbi, functionName: "l2Feed" }),
  l2Client.readContract({ address: feedAddress, abi: feedAbi, functionName: "l1Reporter" }),
]);
if (configuredChildChainId !== BigInt(robinhoodChainId)) throw new Error("reporter child chain mismatch");
if (getAddress(configuredFeed) !== feedAddress) throw new Error("reporter L2 feed mismatch");
if (getAddress(configuredReporter) !== reporterAddress) throw new Error("feed L1 reporter mismatch");
await sampleAvailability();
const timer = setInterval(sampleAvailability, pollInterval);
timer.unref();

createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") {
      respond(response, 200, { ok: true, observer: account.address, ...tracker.snapshot() });
      return;
    }
    if (request.method !== "POST") {
      respond(response, 404, { error: "not found" });
      return;
    }
    const body = await readJson(request);
    if (request.url === "/heartbeat") {
      respond(response, 200, await signHeartbeat(body.heartbeat));
      return;
    }
    if (request.url === "/status") {
      respond(response, 200, await signStatus(body.report));
      return;
    }
    respond(response, 404, { error: "not found" });
  } catch (error) {
    respond(response, 400, { error: error instanceof Error ? error.message : "request failed" });
  }
}).listen(port, host, () => {
  process.stdout.write(`observer ${account.address} listening on ${host}:${port}\n`);
});
