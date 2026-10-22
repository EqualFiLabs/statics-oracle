import { readFileSync } from "node:fs";
import { createPublicClient, getAddress, http, keccak256 } from "viem";

import { feedAbi, reporterAbi } from "./abi.mjs";
import { observerSetHash, validateDeploymentManifest } from "./deployment.mjs";

export const MAINNET_DEPLOYMENT = new URL("../../deployments/robinhood-mainnet.json", import.meta.url);

export function readMainnetDeployment() {
  return JSON.parse(readFileSync(MAINNET_DEPLOYMENT, "utf8"));
}

function validatedMainnet(raw) {
  const deployment = validateDeploymentManifest(raw, { requireDeployment: true });
  if (deployment.chains.ethereum.chainId !== 1 || deployment.chains.robinhood.chainId !== 4663) {
    throw new Error("asset manifest requires the mainnet deployment pair");
  }
  return deployment;
}

export function recordedSequencerConfiguration(raw = readMainnetDeployment()) {
  const deployment = validatedMainnet(raw);
  return {
    feed: deployment.contracts.feed.address,
    // Retain the existing asset manifest's address presentation.
    l1Reporter: deployment.contracts.reporter.address.toLowerCase(),
    l1Inbox: deployment.chains.ethereum.delayedInbox,
    observerSetHash: deployment.configuration.calculatedObserverSetHash,
    threshold: deployment.configuration.threshold,
  };
}

export function validateAssetSequencer(manifest, raw = readMainnetDeployment()) {
  const deployment = validatedMainnet(raw);
  if (manifest.chainId !== deployment.chains.robinhood.chainId) {
    throw new Error("asset manifest chainId differs from deployment manifest");
  }
  const expected = recordedSequencerConfiguration(raw);
  for (const field of ["feed", "l1Reporter", "l1Inbox"]) {
    if (getAddress(manifest.sequencer?.[field]) !== getAddress(expected[field])) {
      throw new Error(`asset sequencer.${field} differs from deployment manifest`);
    }
  }
  for (const field of ["threshold", "observerSetHash"]) {
    if (manifest.sequencer?.[field] !== expected[field]) {
      throw new Error(`asset sequencer.${field} differs from deployment manifest`);
    }
  }
  return deployment;
}

async function readSnapshot(client, contract, abi, bindingFunction) {
  // Pin all reads on each chain to one block; do not combine values from different heads.
  const [chainId, block] = await Promise.all([client.getChainId(), client.getBlock()]);
  const names = ["observers", "threshold", "observerSetVersion", bindingFunction];
  const [values, code] = await Promise.all([
    Promise.all(names.map((functionName) => client.readContract({
      address: contract.address, abi, functionName, blockNumber: block.number,
    }))),
    client.getCode({ address: contract.address, blockNumber: block.number }),
  ]);
  if (!code || code === "0x") throw new Error("sequencer contract has no runtime code");
  return {
    chainId,
    blockNumber: block.number,
    blockHash: block.hash,
    observers: values[0],
    threshold: Number(values[1]),
    version: values[2],
    binding: values[3],
    runtimeCodeHash: keccak256(code),
  };
}

export function validateSequencerSnapshots({ reporter, feed }, raw) {
  const deployment = validatedMainnet(raw);
  for (const [name, snapshot, chain, binding] of [
    ["reporter", reporter, deployment.chains.ethereum, deployment.contracts.feed.address],
    ["feed", feed, deployment.chains.robinhood, deployment.contracts.reporter.address],
  ]) {
    if (snapshot.chainId !== chain.chainId) throw new Error(`${name} RPC chainId mismatch`);
    if (snapshot.runtimeCodeHash !== deployment.contracts[name].runtimeCodeHash) {
      throw new Error(`${name} runtime code hash differs from deployment manifest`);
    }
    if (getAddress(snapshot.binding) !== binding) throw new Error(`${name} contract binding mismatch`);
    if (snapshot.threshold !== deployment.configuration.threshold) {
      throw new Error(`${name} threshold differs from deployment manifest`);
    }
    const actual = snapshot.observers.map((value) => getAddress(value));
    if (actual.join(",") !== deployment.configuration.observers.join(",")) {
      throw new Error(`${name} observers differ from deployment manifest`);
    }
    if (observerSetHash(actual, snapshot.threshold) !== deployment.configuration.observerSetHash) {
      throw new Error(`${name} observer-set hash differs from deployment manifest`);
    }
    if (snapshot.version <= 0n) throw new Error(`${name} observer set is not initialized`);
  }
  if (reporter.version !== feed.version) throw new Error("L1 and L2 observer-set versions differ");
}

export async function verifyLiveSequencer({
  manifest,
  deployment = readMainnetDeployment(),
  ethereumRpcUrl,
  robinhoodRpcUrl,
  clients,
}) {
  const normalized = validateAssetSequencer(manifest, deployment);
  if (!clients && (!ethereumRpcUrl || !robinhoodRpcUrl)) {
    throw new Error("ETH_MAINNET and ROBINHOOD_MAINNET are required for live sequencer verification");
  }
  const transport = (url) => http(url, { timeout: 20_000, retryCount: 1 });
  const l1 = clients?.ethereum ?? createPublicClient({ transport: transport(ethereumRpcUrl) });
  const l2 = clients?.robinhood ?? createPublicClient({ transport: transport(robinhoodRpcUrl) });
  const [reporter, feed] = await Promise.all([
    readSnapshot(l1, normalized.contracts.reporter, reporterAbi, "l2Feed"),
    readSnapshot(l2, normalized.contracts.feed, feedAbi, "l1Reporter"),
  ]);
  validateSequencerSnapshots({ reporter, feed }, deployment);
  return { reporter, feed };
}
