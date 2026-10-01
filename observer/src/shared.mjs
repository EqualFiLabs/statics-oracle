export const POLL_INTERVAL_MS = 30_000;
export const HEARTBEAT_INTERVAL_SECONDS = 5n * 60n;
export const LEASE_SECONDS = 15n * 60n;
export const STATUS_VALIDITY_SECONDS = 5n * 60n;
export const MAX_HEAD_AGE_SECONDS = 60n;
export const REQUIRED_CONSECUTIVE_SAMPLES = 3;

export const ObserverState = Object.freeze({
  UNKNOWN: "UNKNOWN",
  HEALTHY: "HEALTHY",
  IMPAIRED: "IMPAIRED",
});

export class AvailabilityTracker {
  constructor(required = REQUIRED_CONSECUTIVE_SAMPLES) {
    if (!Number.isInteger(required) || required < 1) throw new Error("required must be positive");
    this.required = required;
    this.state = ObserverState.UNKNOWN;
    this.consecutiveSuccesses = 0;
    this.consecutiveFailures = 0;
    this.lastSampleAt = null;
    this.lastError = null;
  }

  record(success, sampledAt = Date.now(), error = null) {
    this.lastSampleAt = sampledAt;
    if (success) {
      this.consecutiveSuccesses += 1;
      this.consecutiveFailures = 0;
      this.lastError = null;
      if (this.consecutiveSuccesses >= this.required) this.state = ObserverState.HEALTHY;
    } else {
      this.consecutiveFailures += 1;
      this.consecutiveSuccesses = 0;
      this.lastError = error instanceof Error ? error.message : String(error ?? "sample failed");
      if (this.consecutiveFailures >= this.required) this.state = ObserverState.IMPAIRED;
    }
    return this.snapshot();
  }

  snapshot() {
    return {
      state: this.state,
      consecutiveSuccesses: this.consecutiveSuccesses,
      consecutiveFailures: this.consecutiveFailures,
      lastSampleAt: this.lastSampleAt,
      lastError: this.lastError,
    };
  }
}

export function parseQuantity(value, field) {
  try {
    return BigInt(value);
  } catch {
    throw new Error(`${field} is not an integer`);
  }
}

function normalizeHash(value, field) {
  const hash = String(value).toLowerCase();
  if (!/^0x[0-9a-f]{64}$/.test(hash)) throw new Error(`${field} is not bytes32`);
  return hash;
}

export function normalizeHeartbeat(value) {
  if (!value || typeof value !== "object") throw new Error("heartbeat is required");
  return {
    observerSetVersion: parseQuantity(value.observerSetVersion, "observerSetVersion"),
    observedBlockNumber: parseQuantity(value.observedBlockNumber, "observedBlockNumber"),
    observedBlockHash: normalizeHash(value.observedBlockHash, "observedBlockHash"),
    validUntil: parseQuantity(value.validUntil, "validUntil"),
  };
}

export function normalizeStatusReport(value) {
  if (!value || typeof value !== "object") throw new Error("report is required");
  if (typeof value.healthy !== "boolean") throw new Error("healthy must be boolean");
  return {
    observerSetVersion: parseQuantity(value.observerSetVersion, "observerSetVersion"),
    sequence: parseQuantity(value.sequence, "sequence"),
    healthy: value.healthy,
    observedAt: parseQuantity(value.observedAt, "observedAt"),
    validUntil: parseQuantity(value.validUntil, "validUntil"),
  };
}

export function serializeBigInts(value) {
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, typeof item === "bigint" ? item.toString() : item]),
  );
}

export function validateHeartbeat({
  heartbeat,
  expectedObserverSetVersion,
  directHead,
  referenceHead,
  directReferenceBlock,
  referenceBlock,
  now,
}) {
  if (heartbeat.observerSetVersion !== expectedObserverSetVersion) throw new Error("observer set version changed");
  if (heartbeat.observerSetVersion === 0n) throw new Error("observer set is not initialized");
  if (heartbeat.observedBlockNumber > directHead.number) throw new Error("proposed block is ahead of the sequencer feed");
  if (heartbeat.observedBlockNumber >= referenceHead.number) throw new Error("proposed block is not behind the reference head");
  validateObservedHeads({ directHead, referenceHead, directReferenceBlock, now });
  if (referenceBlock.number !== heartbeat.observedBlockNumber || referenceBlock.hash !== heartbeat.observedBlockHash) {
    throw new Error("reference RPC does not agree with the proposal");
  }
  if (heartbeat.validUntil <= now) throw new Error("proposed lease is expired");
  if (heartbeat.validUntil > now + LEASE_SECONDS) throw new Error("proposed lease is too long");
}

export function validateObservedHeads({ directHead, referenceHead, directReferenceBlock, now }) {
  if (referenceHead.number < directHead.number) throw new Error("reference RPC has not reached the sequencer-feed head");
  if (now - directHead.timestamp > MAX_HEAD_AGE_SECONDS) throw new Error("direct sequencer-feed head is stale");
  if (now - referenceHead.timestamp > MAX_HEAD_AGE_SECONDS) throw new Error("reference RPC head is stale");
  if (directHead.timestamp > now + 15n || referenceHead.timestamp > now + 15n) throw new Error("RPC head timestamp is in the future");
  if (directReferenceBlock.number !== directHead.number || directReferenceBlock.hash !== directHead.hash) {
    throw new Error("sequencer feed and reference RPC disagree");
  }
}

export function validateStatusReport({ report, version, sequence, currentHealthy, localState, now }) {
  if (localState === ObserverState.UNKNOWN) throw new Error("observer state is unknown");
  if (report.observerSetVersion !== version) throw new Error("observer set version changed");
  if (report.sequence !== sequence + 1n) throw new Error("status sequence changed");
  if (report.healthy === currentHealthy) throw new Error("status is not a transition");
  if (report.healthy !== (localState === ObserverState.HEALTHY)) throw new Error("proposal disagrees with local state");
  if (report.observedAt > now + 30n || report.observedAt + 300n < now) throw new Error("status observation is stale");
  if (report.validUntil <= now || report.validUntil > report.observedAt + 600n) throw new Error("status validity is invalid");
}

export function heartbeatDue(healthyUntil, now) {
  return healthyUntil <= now + (LEASE_SECONDS - HEARTBEAT_INTERVAL_SECONDS);
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
