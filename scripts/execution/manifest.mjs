import { readFileSync } from "node:fs";

export const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
export const WORD = /^0x[0-9a-fA-F]{64}$/;
const zero = (value) => /^0x0+$/.test(value);
const uint = (value, max, min = 0) => Number.isSafeInteger(value) && value >= min && value <= max;
function requireValue(condition, message) { if (!condition) throw new Error(message); }
export function validateManifest(manifest, { deployable = false } = {}) {
  requireValue(manifest?.schemaVersion === 1, "unsupported stream manifest schema");
  requireValue([4663, 46630].includes(manifest.chainId), "unsupported execution chain");
  requireValue(ADDRESS.test(manifest.verifierProxy) && !zero(manifest.verifierProxy), "invalid verifier address");
  requireValue(WORD.test(manifest.verifierCodeHash) && !zero(manifest.verifierCodeHash), "invalid verifier runtime hash");
  requireValue(uint(manifest.verifiedBlock, Number.MAX_SAFE_INTEGER, 1), "missing pinned binding block");
  const bound = manifest.maxReportBundleSize;
  requireValue(bound === null || uint(bound, 255, 1), "invalid bundle bound");
  requireValue(typeof manifest.productionParametersRatified === "boolean", "missing parameter review status");
  requireValue(Array.isArray(manifest.markets) && manifest.markets.length > 0, "missing markets");
  const ids = new Set(); const labels = new Set();
  for (const row of manifest.markets) {
    requireValue(/^[A-Z0-9_]{1,32}$/.test(row.label) && !labels.has(row.label), "invalid or duplicate market label");
    requireValue(WORD.test(row.marketId) && !zero(row.marketId) && !ids.has(row.marketId.toLowerCase()), "invalid or duplicate market ID");
    labels.add(row.label); ids.add(row.marketId.toLowerCase());
    requireValue(WORD.test(row.streamId) && row.streamId.slice(0,6).toLowerCase() === "0x0003" && row.reportSchema === 3, "unsupported stream schema");
    requireValue(uint(row.streamDecimals, 18), "unsupported stream precision");
    requireValue(["CANDIDATE", "ENABLED", "DISABLED"].includes(row.status), "invalid market lifecycle");
    for (const field of ["executionDelay", "maxReportWindow"]) requireValue(row[field] === null || uint(row[field], 0xffffffff, 1), "invalid execution timing");
    const review = row.verification;
    requireValue(review && /^https:\/\//.test(review.source) && Number.isFinite(Date.parse(review.verifiedAt)) && Number.isFinite(Date.parse(review.deprecationCheckedAt)), "missing stream provenance");
    requireValue(["live", "testing"].includes(review.directoryStatus), "deprecated or inactive stream");
    requireValue(typeof review.authenticatedOnRobinhood === "boolean", "missing authentication qualification");
    if (row.status === "ENABLED" || deployable) {
      requireValue(bound !== null && row.executionDelay !== null && row.maxReportWindow !== null, "unratified execution parameters");
      requireValue(manifest.productionParametersRatified && review.authenticatedOnRobinhood, "execution qualification pending");
      requireValue(manifest.chainId !== 4663 || review.directoryStatus === "live", "testing stream cannot enable on mainnet");
    }
  }
  if (deployable || manifest.markets.some((row) => row.status === "ENABLED")) {
    requireValue(ADDRESS.test(manifest.sequencer?.feed) && !zero(manifest.sequencer.feed), "missing sequencer binding");
    requireValue(WORD.test(manifest.sequencer.codeHash) && !zero(manifest.sequencer.codeHash), "missing sequencer runtime hash");
    requireValue(uint(manifest.sequencer.gracePeriod,0xffffffff), "invalid sequencer grace");
  }
  return manifest;
}
export function readManifest(path, options) { return validateManifest(JSON.parse(readFileSync(path,"utf8")), options); }

/** Report-only metadata comparison. Never mutate the reviewed manifest. */
export function detectStreamDrift(manifest, discovered) {
  validateManifest(manifest);
  const changes = [];
  for (const row of manifest.markets) {
    const live = discovered.find((item) => item.feedId?.toLowerCase() === row.streamId.toLowerCase());
    if (!live) { changes.push({ market: row.label, field: "availability" }); continue; }
    for (const [field, expected] of [["decimals",row.streamDecimals],["status",row.verification.directoryStatus]]) {
      if (live[field] !== expected) changes.push({ market: row.label, field });
    }
    if (live.reportSchema !== undefined && live.reportSchema !== 3) changes.push({ market: row.label, field: "schema" });
  }
  return changes;
}
