import { createServer } from "node:http";
import { createPublicClient, defineChain, getAddress, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { eip712Domain, feedAbi, observationTypes } from "./abi.mjs";
import { assertRobinhoodRpc, getBlock, readSequencerFeedHead, waitForBlock } from "./rpc.mjs";
import {
  normalizeObservation,
  parsePrivateKey,
  requireEnv,
  serializeObservation,
  validateObservation,
} from "./shared.mjs";

const feedAddress = getAddress(requireEnv("SEQUENCER_SIGNAL_FEED"));
const directFeedUrl = requireEnv("DIRECT_SEQUENCER_FEED_URL");
const referenceUrl = requireEnv("REFERENCE_RPC_URL");
const account = privateKeyToAccount(parsePrivateKey("OBSERVER_PRIVATE_KEY"));
const host = process.env.OBSERVER_HOST ?? "127.0.0.1";
const port = Number(process.env.OBSERVER_PORT ?? "8787");
let lastSignedBlock = -1n;
let lastSignedHash;
const chain = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [referenceUrl] } },
});
const publicClient = createPublicClient({ chain, transport: http() });

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

async function signProposal(rawObservation) {
  const observation = normalizeObservation(rawObservation);
  const [observerSetVersion, onchainLastBlock, authorized] = await Promise.all([
    publicClient.readContract({
      address: feedAddress,
      abi: feedAbi,
      functionName: "observerSetVersion",
    }),
    publicClient.readContract({
      address: feedAddress,
      abi: feedAbi,
      functionName: "lastObservedBlockNumber",
    }),
    publicClient.readContract({
      address: feedAddress,
      abi: feedAbi,
      functionName: "isObserver",
      args: [account.address],
    }),
  ]);
  if (!authorized) throw new Error("signing key is not in the onchain observer set");
  if (observation.observedBlockNumber <= onchainLastBlock) {
    throw new Error("proposed block is not newer than the onchain observation");
  }
  if (observation.observedBlockNumber < lastSignedBlock) {
    throw new Error("proposed block is older than the last signed block");
  }
  if (
    observation.observedBlockNumber === lastSignedBlock &&
    lastSignedHash !== observation.observedBlockHash
  ) {
    throw new Error("refusing a conflicting block at the last signed height");
  }

  const [directHead, referenceBlock] = await Promise.all([
    readSequencerFeedHead(directFeedUrl),
    getBlock(referenceUrl, observation.observedBlockNumber),
  ]);
  const directReferenceBlock = await waitForBlock(referenceUrl, directHead.number);
  const referenceHead = await getBlock(referenceUrl);
  validateObservation({
    observation,
    expectedObserverSetVersion: observerSetVersion,
    directHead,
    referenceHead,
    directReferenceBlock,
    referenceBlock,
    now: BigInt(Math.floor(Date.now() / 1_000)),
  });

  const signature = await account.signTypedData({
    domain: eip712Domain(feedAddress),
    types: observationTypes,
    primaryType: "Observation",
    message: observation,
  });
  lastSignedBlock = observation.observedBlockNumber;
  lastSignedHash = observation.observedBlockHash;
  return { observer: account.address, observation: serializeObservation(observation), signature };
}

await Promise.all([assertRobinhoodRpc(referenceUrl), readSequencerFeedHead(directFeedUrl)]);

createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") {
      respond(response, 200, { ok: true, observer: account.address });
      return;
    }
    if (request.method !== "POST" || request.url !== "/observe") {
      respond(response, 404, { error: "not found" });
      return;
    }
    respond(response, 200, await signProposal((await readJson(request)).observation));
  } catch (error) {
    respond(response, 400, { error: error instanceof Error ? error.message : "request failed" });
  }
}).listen(port, host, () => {
  process.stdout.write(`observer ${account.address} listening on ${host}:${port}\n`);
});
