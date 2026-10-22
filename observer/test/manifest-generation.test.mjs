import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { encodeAbiParameters } from "viem";

import { generateManifest, REQUESTED_ASSETS, SOURCES } from "../../scripts/generate-whitelist.mjs";

const manifest = JSON.parse(readFileSync(new URL("../../config/robinhood-mainnet.assets.json", import.meta.url)));
const encode = (types, values) => encodeAbiParameters(types.map((type) => ({ type })), values);

test("generation reproduces every reviewed field under the recorded source/RPC inputs", async (t) => {
  const byToken = new Map(manifest.assets.map((row) => [row.token.toLowerCase(), row]));
  const byFeed = new Map(manifest.assets.map((row) => [row.feed.toLowerCase(), row]));
  const bySymbol = new Map(manifest.assets.map((row) => [row.symbol, row]));
  const registry = { assets: REQUESTED_ASSETS.filter((a) => ["STOCK", "ETF"].includes(a.kind)).map((a) => ({
    id: bySymbol.get(a.symbol).verification.robinhoodAssetId,
    tokenSymbol: a.symbol,
    tokenDecimals: a.tokenDecimals,
    status: "ASSET_STATUS_ACTIVE",
    deployments: [{ chainId: 4663, contractAddress: a.token }],
  })) };
  const directory = REQUESTED_ASSETS.map((a) => ({
    proxyAddress: a.feed,
    decimals: bySymbol.get(a.symbol).feedDecimals,
    heartbeat: bySymbol.get(a.symbol).heartbeat,
    name: bySymbol.get(a.symbol).chainlinkDirectoryName,
    docs: { baseAsset: a.feedBase },
  }));
  const blockTag = `0x${manifest.verifiedBlock.toString(16)}`;
  const request = ({ id, method, params }) => {
    let result;
    if (method === "eth_chainId") result = "0x1237";
    else if (method === "eth_blockNumber") result = blockTag;
    else if (method === "eth_getBlockByNumber") {
      assert.equal(params[0], blockTag);
      result = { timestamp: `0x${(Date.parse(manifest.verifiedBlockTimestamp) / 1000).toString(16)}` };
    } else {
      assert.equal(params[1], blockTag);
      if (method === "eth_getCode") result = "0x6000";
      else {
        assert.equal(method, "eth_call");
        const { to, data } = params[0];
        const token = byToken.get(to.toLowerCase());
        const feed = byFeed.get(to.toLowerCase());
        if (data === "0x313ce567") result = encode(["uint8"], [token?.tokenDecimals ?? feed.feedDecimals]);
        else if (data === "0x7284e416") result = encode(["string"], [feed.feedDescription]);
        else if (data === "0xfeaf968c") {
          const { roundId, updatedAt } = feed.verification;
          result = encode(["uint80", "int256", "uint256", "uint256", "uint80"], [BigInt(roundId), 1n, BigInt(updatedAt), BigInt(updatedAt), BigInt(roundId)]);
        } else if (data === "0x7706ba52") result = encode(["bool"], [false]);
        else if (data === "0xc2eeeebd") result = encode(["address"], [token.l1Origin]);
        else if (data.startsWith("0xa7e28d48")) {
          const origin = `0x${data.slice(-40)}`;
          const canonical = manifest.assets.find((a) => a.l1Origin?.toLowerCase() === origin.toLowerCase());
          result = encode(["address"], [canonical.token]);
        } else assert.fail(`unexpected selector ${data}`);
      }
    }
    return { jsonrpc: "2.0", id, result };
  };
  t.mock.method(globalThis, "fetch", async (url, options) => {
    let payload;
    if (url === SOURCES.robinhoodAssets) payload = registry;
    else if (url === SOURCES.chainlinkDirectory) payload = directory;
    else {
      assert.equal(url, "https://mock-rpc.invalid");
      const body = JSON.parse(options.body);
      payload = Array.isArray(body) ? body.map(request) : request(body);
    }
    return new Response(JSON.stringify(payload));
  });
  const generated = await generateManifest({
    rpcUrl: "https://mock-rpc.invalid",
    blockNumber: manifest.verifiedBlock,
    generatedAt: manifest.generatedAt,
  });
  assert.deepEqual(generated, manifest);
});
