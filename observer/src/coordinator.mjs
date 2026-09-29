import {
  createPublicClient,
  createWalletClient,
  defineChain,
  getAddress,
  http,
  recoverTypedDataAddress,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { eip712Domain, feedAbi, observationTypes } from "./abi.mjs";
import { recoverAuthorizedSignatures } from "./quorum.mjs";
import { assertRobinhoodRpc, getBlock, readSequencerFeedHead, waitForBlock } from "./rpc.mjs";
import {
  LEASE_SECONDS,
  normalizeObservation,
  parsePrivateKey,
  requireEnv,
  serializeObservation,
  validateObservation,
} from "./shared.mjs";

const chain = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [requireEnv("COORDINATOR_RPC_URL")] } },
});
const feedAddress = getAddress(requireEnv("SEQUENCER_SIGNAL_FEED"));
const directFeedUrl = requireEnv("DIRECT_SEQUENCER_FEED_URL");
const referenceUrl = requireEnv("REFERENCE_RPC_URL");
const observerUrls = requireEnv("OBSERVER_URLS").split(",").map((value) => value.trim());
const account = privateKeyToAccount(parsePrivateKey("RELAYER_PRIVATE_KEY"));
const pollInterval = Number(process.env.POLL_INTERVAL_MS ?? "30000");
const runOnce = process.env.RUN_ONCE === "true";
const publicClient = createPublicClient({ chain, transport: http() });
const walletClient = createWalletClient({ account, chain, transport: http() });

async function requestSignature(url, observation) {
  const response = await fetch(new URL("/observe", url), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ observation: serializeObservation(observation) }),
    signal: AbortSignal.timeout(12_000),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(`observer refused: ${payload.error ?? response.status}`);
  return payload;
}

async function runRound() {
  const [observerSetVersion, lastObservedBlockNumber, threshold, observers, directHead] =
    await Promise.all([
      publicClient.readContract({ address: feedAddress, abi: feedAbi, functionName: "observerSetVersion" }),
      publicClient.readContract({ address: feedAddress, abi: feedAbi, functionName: "lastObservedBlockNumber" }),
      publicClient.readContract({ address: feedAddress, abi: feedAbi, functionName: "threshold" }),
      publicClient.readContract({ address: feedAddress, abi: feedAbi, functionName: "observers" }),
      readSequencerFeedHead(directFeedUrl),
    ]);
  if (directHead.number === 0n) throw new Error("sequencer feed returned genesis");
  const targetBlock = directHead.number - 1n;
  if (targetBlock <= lastObservedBlockNumber) throw new Error("no newer mutually observable block");
  const [directReferenceBlock, referenceBlock] = await Promise.all([
    waitForBlock(referenceUrl, directHead.number),
    waitForBlock(referenceUrl, targetBlock),
  ]);
  const referenceHead = await getBlock(referenceUrl);
  const now = BigInt(Math.floor(Date.now() / 1_000));
  const observation = normalizeObservation({
    observerSetVersion,
    observedBlockNumber: targetBlock,
    observedBlockHash: referenceBlock.hash,
    validUntil: now + LEASE_SECONDS,
  });
  validateObservation({
    observation,
    expectedObserverSetVersion: observerSetVersion,
    directHead,
    referenceHead,
    directReferenceBlock,
    referenceBlock,
    now,
  });

  const settled = await Promise.allSettled(
    observerUrls.map((url) => requestSignature(url, observation)),
  );
  const quorum = await recoverAuthorizedSignatures({
    settled,
    authorizedObservers: observers,
    recover: async (signature) =>
      await recoverTypedDataAddress({
        domain: eip712Domain(feedAddress),
        types: observationTypes,
        primaryType: "Observation",
        message: observation,
        signature,
      }),
  });
  if (quorum.length < threshold) {
    throw new Error(`observer quorum unavailable: received ${quorum.length}, require ${threshold}`);
  }

  const args = [observation, quorum.map((value) => value.signature)];
  const { request } = await publicClient.simulateContract({
    account,
    address: feedAddress,
    abi: feedAbi,
    functionName: "submitObservation",
    args,
  });
  const transactionHash = await walletClient.writeContract(request);
  await publicClient.waitForTransactionReceipt({ hash: transactionHash });
  process.stdout.write(
    `renewed through ${observation.validUntil} from block ${observation.observedBlockNumber}: ${transactionHash}\n`,
  );
}

await Promise.all([
  readSequencerFeedHead(directFeedUrl),
  assertRobinhoodRpc(referenceUrl),
  assertRobinhoodRpc(requireEnv("COORDINATOR_RPC_URL")),
]);

do {
  try {
    await runRound();
  } catch (error) {
    process.stderr.write(`${new Date().toISOString()} round failed: ${error instanceof Error ? error.message : "unknown error"}\n`);
  }
  if (!runOnce) await new Promise((resolve) => setTimeout(resolve, pollInterval));
} while (!runOnce);
