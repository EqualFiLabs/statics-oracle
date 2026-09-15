#!/usr/bin/env node

import { readFileSync } from "node:fs";

import {
  CHAIN_ID,
  REQUESTED_ASSETS,
  SOURCES,
  generateManifest,
} from "./generate-whitelist.mjs";

const DEFAULT_MANIFEST_PATH = "config/robinhood-mainnet.assets.json";

function parseArgs(argv) {
  const options = { manifest: DEFAULT_MANIFEST_PATH };
  for (let index = 0; index < argv.length; ++index) {
    if (argv[index] === "--block") options.block = Number(argv[++index]);
    else if (argv[index] === "--manifest") options.manifest = argv[++index];
    else throw new Error(`Unknown argument: ${argv[index]}`);
  }
  if (!options.manifest) throw new Error("--manifest requires a path");
  if (options.block !== undefined && (!Number.isSafeInteger(options.block) || options.block < 0)) {
    throw new Error("--block must be a non-negative safe integer");
  }
  return options;
}

function addressEqual(a, b) {
  return typeof a === "string" && typeof b === "string" && a.toLowerCase() === b.toLowerCase();
}

async function fetchJson(url, label) {
  const response = await fetch(url, { headers: { accept: "application/json" } });
  if (!response.ok) throw new Error(`${label} returned HTTP ${response.status}`);
  try {
    return await response.json();
  } catch (error) {
    throw new Error(`${label} returned malformed JSON: ${error.message}`);
  }
}

function describeAddresses(values) {
  return values.length === 0 ? "none" : values.join(", ");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!process.env.ROBINHOOD_MAINNET) throw new Error("ROBINHOOD_MAINNET is required");

  const manifestBytesBefore = readFileSync(options.manifest);
  let manifest;
  try {
    manifest = JSON.parse(manifestBytesBefore.toString("utf8"));
  } catch (error) {
    throw new Error(`Manifest is malformed JSON: ${error.message}`);
  }

  const hardFailures = [];
  const reviewWarnings = [];
  if (manifest.schemaVersion !== 1) hardFailures.push(`unsupported schemaVersion ${manifest.schemaVersion}`);
  if (manifest.chainId !== CHAIN_ID) hardFailures.push(`manifest chainId is not ${CHAIN_ID}`);
  if (!Array.isArray(manifest.assets)) hardFailures.push("manifest assets must be an array");
  if (hardFailures.length > 0) return report(hardFailures, reviewWarnings, null);

  const manifestBySymbol = new Map();
  const tokenOwners = new Map();
  for (const row of manifest.assets) {
    if (manifestBySymbol.has(row.symbol)) hardFailures.push(`duplicate manifest symbol ${row.symbol}`);
    manifestBySymbol.set(row.symbol, row);
    const tokenKey = row.token?.toLowerCase();
    if (tokenOwners.has(tokenKey)) {
      hardFailures.push(`duplicate manifest token ${row.token} for ${tokenOwners.get(tokenKey)} and ${row.symbol}`);
    }
    tokenOwners.set(tokenKey, row.symbol);
  }
  if (manifest.assets.length !== REQUESTED_ASSETS.length) {
    hardFailures.push(`manifest has ${manifest.assets.length} rows; expected ${REQUESTED_ASSETS.length}`);
  }
  if (manifest.assetCount !== manifest.assets.length) {
    hardFailures.push(`manifest assetCount ${manifest.assetCount} does not match assets length`);
  }

  for (const requested of REQUESTED_ASSETS) {
    const row = manifestBySymbol.get(requested.symbol);
    if (!row) {
      hardFailures.push(`missing manifest row ${requested.symbol}`);
      continue;
    }
    if (!addressEqual(row.token, requested.token)) {
      hardFailures.push(`${requested.symbol} approved token changed: ${row.token} != ${requested.token}`);
    }
    if (!addressEqual(row.feed, requested.feed)) {
      hardFailures.push(`${requested.symbol} approved feed changed: ${row.feed} != ${requested.feed}`);
    }
    if (row.kind !== requested.kind) hardFailures.push(`${requested.symbol} kind changed`);
    if (row.status !== requested.status) hardFailures.push(`${requested.symbol} lifecycle target changed`);
    if (row.tokenDecimals !== requested.tokenDecimals) {
      hardFailures.push(`${requested.symbol} approved token decimals changed`);
    }
    if (row.maxAge !== row.heartbeat || row.maxAgePolicy !== "CHAINLINK_DIRECTORY_HEARTBEAT") {
      hardFailures.push(`${requested.symbol} maxAge no longer matches its approved heartbeat policy`);
    }
    const shouldCheckPause = requested.kind === "STOCK" || requested.kind === "ETF";
    if (row.checkOraclePause !== shouldCheckPause) {
      hardFailures.push(`${requested.symbol} stock pause policy changed`);
    }
  }

  const [robinhoodPayload, chainlinkDirectory] = await Promise.all([
    fetchJson(SOURCES.robinhoodAssets, "Robinhood asset registry"),
    fetchJson(SOURCES.chainlinkDirectory, "Chainlink feed directory"),
  ]);
  if (!Array.isArray(robinhoodPayload?.assets)) throw new Error("Robinhood registry is missing assets[]");
  if (!Array.isArray(chainlinkDirectory)) throw new Error("Chainlink directory must be an array");

  for (const requested of REQUESTED_ASSETS) {
    const row = manifestBySymbol.get(requested.symbol);
    if (!row) continue;

    if (requested.kind === "STOCK" || requested.kind === "ETF") {
      const sourceAsset = robinhoodPayload.assets.find(
        (asset) => asset.id === row.verification?.robinhoodAssetId,
      );
      if (!sourceAsset) {
        hardFailures.push(`${requested.symbol} Robinhood asset ID is missing from the canonical registry`);
      } else {
        const deployments = (sourceAsset.deployments ?? [])
          .filter((deployment) => deployment.chainId === CHAIN_ID)
          .map((deployment) => deployment.contractAddress);
        if (!deployments.some((address) => addressEqual(address, row.token))) {
          hardFailures.push(
            `${requested.symbol} Robinhood token drift: approved ${row.token}; canonical ${describeAddresses(deployments)}`,
          );
        }
        if (sourceAsset.tokenSymbol !== requested.symbol) {
          hardFailures.push(`${requested.symbol} Robinhood symbol identity changed to ${sourceAsset.tokenSymbol}`);
        }
        if (sourceAsset.status !== "ASSET_STATUS_ACTIVE") {
          hardFailures.push(`${requested.symbol} Robinhood asset is no longer active`);
        }
      }
    }

    const exactFeeds = chainlinkDirectory.filter((feed) => addressEqual(feed.proxyAddress, row.feed));
    if (exactFeeds.length !== 1) {
      const possible = chainlinkDirectory
        .filter((feed) => feed.docs?.baseAsset === requested.feedBase)
        .map((feed) => feed.proxyAddress);
      hardFailures.push(
        `${requested.symbol} Chainlink feed drift: approved ${row.feed}; matching base proxies ${describeAddresses(possible)}`,
      );
      continue;
    }
    const sourceFeed = exactFeeds[0];
    if (sourceFeed.docs?.baseAsset !== requested.feedBase) {
      hardFailures.push(`${requested.symbol} Chainlink base identity changed to ${sourceFeed.docs?.baseAsset}`);
    }
    if (sourceFeed.decimals !== row.feedDecimals) {
      hardFailures.push(`${requested.symbol} Chainlink directory decimals changed`);
    }
    if (sourceFeed.name !== row.chainlinkDirectoryName) {
      reviewWarnings.push(
        `${requested.symbol} Chainlink directory name changed: ${row.chainlinkDirectoryName} -> ${sourceFeed.name}`,
      );
    }
    if (sourceFeed.heartbeat !== row.heartbeat) {
      reviewWarnings.push(
        `${requested.symbol} Chainlink heartbeat changed: ${row.heartbeat} -> ${sourceFeed.heartbeat}; review maxAge without auto-updating`,
      );
    }
  }

  let liveManifest = null;
  try {
    liveManifest = await generateManifest({
      rpcUrl: process.env.ROBINHOOD_MAINNET,
      blockNumber: options.block,
      generatedAt: manifest.generatedAt,
    });
  } catch (error) {
    hardFailures.push(`live contract/source verification failed: ${error.message}`);
  }

  if (liveManifest) {
    const liveBySymbol = new Map(liveManifest.assets.map((row) => [row.symbol, row]));
    for (const row of manifest.assets) {
      const live = liveBySymbol.get(row.symbol);
      if (!live) {
        hardFailures.push(`${row.symbol} omitted from live verification`);
        continue;
      }
      if (!addressEqual(row.token, live.token) || !addressEqual(row.feed, live.feed)) {
        hardFailures.push(`${row.symbol} live exact identity differs from approved identity`);
      }
      if (row.tokenDecimals !== live.tokenDecimals || row.feedDecimals !== live.feedDecimals) {
        hardFailures.push(`${row.symbol} live decimals differ from approved decimals`);
      }
      if (row.feedDescription !== live.feedDescription || row.feedDescriptionHash !== live.feedDescriptionHash) {
        hardFailures.push(`${row.symbol} live feed description differs from approved description hash`);
      }
    }
  }

  for (const row of manifest.assets.filter((asset) => asset.status === "CANDIDATE")) {
    reviewWarnings.push(`${row.symbol} remains CANDIDATE pending wrapper provenance, liquidity, and risk review`);
  }
  if (manifest.sequencer?.verified !== true || !manifest.sequencer?.feed) {
    reviewWarnings.push("canonical Robinhood sequencer feed and recovery grace policy remain unresolved");
  }

  const manifestBytesAfter = readFileSync(options.manifest);
  if (!manifestBytesBefore.equals(manifestBytesAfter)) {
    hardFailures.push("verifier mutated the checked-in manifest");
  }
  report(hardFailures, reviewWarnings, liveManifest?.verifiedBlock ?? null);
}

function report(hardFailures, reviewWarnings, verifiedBlock) {
  for (const warning of reviewWarnings) process.stderr.write(`REVIEW WARNING: ${warning}\n`);
  for (const failure of hardFailures) process.stderr.write(`HARD FAILURE: ${failure}\n`);
  if (hardFailures.length > 0) {
    process.stderr.write(`whitelist verification failed with ${hardFailures.length} hard failure(s)\n`);
    process.exitCode = 1;
    return;
  }
  process.stdout.write(
    `whitelist verification passed for ${REQUESTED_ASSETS.length} assets` +
      (verifiedBlock === null ? "" : ` at Robinhood block ${verifiedBlock}`) +
      ` with ${reviewWarnings.length} review warning(s)\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`verify-whitelist: ${error.message}\n`);
  process.exitCode = 1;
});
