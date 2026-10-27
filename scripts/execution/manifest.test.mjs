import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateManifest, detectStreamDrift } from "./manifest.mjs";
const source = JSON.parse(readFileSync(new URL("../../config/robinhood-mainnet.streams.json",import.meta.url)));
test("candidates cannot be treated as launch configuration", () => {
  assert.equal(validateManifest(source),source);
  assert.throws(() => validateManifest(source,{ deployable:true }), /unratified/);
  const enabled=structuredClone(source);enabled.markets[0].status="ENABLED";
  assert.throws(() => validateManifest(enabled), /unratified/);
});
test("schema precision duplicate IDs and timing fail closed", () => {
  for (const mutate of [m=>m.markets[0].streamDecimals=19,m=>m.markets[0].streamId="0x"+"11".repeat(32),m=>m.markets[1].marketId=m.markets[0].marketId,m=>m.markets[0].executionDelay=0,m=>m.markets[0].verification.directoryStatus="deprecated"]) {
    const bad=structuredClone(source);mutate(bad);assert.throws(()=>validateManifest(bad));
  }
});
test("discovery drift never changes reviewed bindings", () => {
  const before=JSON.stringify(source);
  assert.deepEqual(detectStreamDrift(source,[]).map(x=>x.field),["availability","availability"]);
  const discovered=source.markets.map(r=>({feedId:r.streamId,decimals:r.streamDecimals,status:r.verification.directoryStatus,reportSchema:3}));
  assert.deepEqual(detectStreamDrift(source,discovered),[]);
  discovered[0].decimals=8;assert.deepEqual(detectStreamDrift(source,discovered),[{market:"BTC_USD",field:"decimals"}]);
  assert.equal(JSON.stringify(source),before);
});
