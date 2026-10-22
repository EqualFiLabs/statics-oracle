#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { sanitizeOperationalError } from "../observer/src/deployment.mjs";
import {
  readMainnetDeployment,
  validateAssetSequencer,
  verifyLiveSequencer,
} from "../observer/src/sequencer-config.mjs";

async function main() {
  let live = false;
  let manifestPath = new URL("../config/robinhood-mainnet.assets.json", import.meta.url);
  const args = process.argv.slice(2);
  for (let index = 0; index < args.length; ++index) {
    if (args[index] === "--live") live = true;
    else if (args[index] === "--manifest" && args[index + 1]) manifestPath = args[++index];
    else throw new Error(`Unknown or incomplete argument: ${args[index]}`);
  }
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const deployment = readMainnetDeployment();
  validateAssetSequencer(manifest, deployment);
  if (live) {
    const snapshots = await verifyLiveSequencer({
      manifest,
      deployment,
      ethereumRpcUrl: process.env.ETH_MAINNET,
      robinhoodRpcUrl: process.env.ROBINHOOD_MAINNET,
    });
    process.stdout.write(
      `live sequencer configuration verified at Ethereum block ${snapshots.reporter.blockNumber}` +
      ` and Robinhood block ${snapshots.feed.blockNumber}; version ${snapshots.reporter.version}\n`,
    );
  } else {
    process.stdout.write("asset sequencer configuration matches the reviewed deployment manifest\n");
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    process.stderr.write(`verify-sequencer-config: ${sanitizeOperationalError(error)}\n`);
    process.exitCode = 1;
  });
}
