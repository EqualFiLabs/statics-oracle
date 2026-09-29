export const ROBINHOOD_CHAIN_ID = 4663n;
export const LEASE_SECONDS = 95n;
export const MIN_SIGNED_LEASE_SECONDS = 75n;
export const MAX_HEAD_AGE_SECONDS = 60n;

export function parseQuantity(value, field) {
  try {
    return BigInt(value);
  } catch {
    throw new Error(`${field} is not an integer`);
  }
}

export function normalizeObservation(value) {
  if (!value || typeof value !== "object") throw new Error("observation is required");
  const observedBlockHash = String(value.observedBlockHash).toLowerCase();
  if (!/^0x[0-9a-f]{64}$/.test(observedBlockHash)) {
    throw new Error("observedBlockHash is not bytes32");
  }

  return {
    observerSetVersion: parseQuantity(value.observerSetVersion, "observerSetVersion"),
    observedBlockNumber: parseQuantity(value.observedBlockNumber, "observedBlockNumber"),
    observedBlockHash,
    validUntil: parseQuantity(value.validUntil, "validUntil"),
  };
}

export function serializeObservation(observation) {
  return {
    observerSetVersion: observation.observerSetVersion.toString(),
    observedBlockNumber: observation.observedBlockNumber.toString(),
    observedBlockHash: observation.observedBlockHash,
    validUntil: observation.validUntil.toString(),
  };
}

export function validateObservation({
  observation,
  expectedObserverSetVersion,
  directHead,
  referenceHead,
  directReferenceBlock,
  referenceBlock,
  now,
}) {
  if (observation.observerSetVersion !== expectedObserverSetVersion) {
    throw new Error("observer set version changed");
  }
  if (observation.observerSetVersion === 0n) throw new Error("observer set is not initialized");
  if (observation.observedBlockNumber > directHead.number) {
    throw new Error("proposed block is ahead of the sequencer feed");
  }
  if (observation.observedBlockNumber >= referenceHead.number) {
    throw new Error("proposed block is not behind the reference head");
  }
  if (referenceHead.number < directHead.number) {
    throw new Error("reference RPC has not reached the sequencer-feed head");
  }
  if (now - directHead.timestamp > MAX_HEAD_AGE_SECONDS) {
    throw new Error("direct sequencer-feed head is stale");
  }
  if (now - referenceHead.timestamp > MAX_HEAD_AGE_SECONDS) {
    throw new Error("reference RPC head is stale");
  }
  if (directHead.timestamp > now + 15n || referenceHead.timestamp > now + 15n) {
    throw new Error("RPC head timestamp is in the future");
  }
  if (directReferenceBlock.number !== directHead.number) {
    throw new Error("reference RPC returned the wrong sequencer-feed block");
  }
  if (directReferenceBlock.hash !== directHead.hash) {
    throw new Error("sequencer feed and reference RPC disagree");
  }
  if (referenceBlock.number !== observation.observedBlockNumber) {
    throw new Error("reference RPC returned the wrong block");
  }
  if (
    referenceBlock.hash !== observation.observedBlockHash
  ) {
    throw new Error("reference RPC does not agree with the proposal");
  }
  if (observation.validUntil < now + MIN_SIGNED_LEASE_SECONDS) {
    throw new Error("proposed lease is too short");
  }
  if (observation.validUntil > now + LEASE_SECONDS) {
    throw new Error("proposed lease is too long");
  }
}

export function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

export function parsePrivateKey(name) {
  const value = requireEnv(name);
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new Error(`${name} is not a private key`);
  return value;
}
