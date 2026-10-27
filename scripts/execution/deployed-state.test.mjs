import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {compareDeployment} from "./deployed-state.mjs";
const candidate=JSON.parse(readFileSync(new URL("../../config/robinhood-mainnet.streams.json",import.meta.url)));
function fixture(){const manifest=structuredClone(candidate);manifest.maxReportBundleSize=5;manifest.productionParametersRatified=true;
for(const r of manifest.markets){r.executionDelay=10;r.maxReportWindow=30;r.status="ENABLED";r.verification.authenticatedOnRobinhood=true;}
const record={chainId:4663,oracle:"0x"+"12".repeat(20),owner:"0x"+"34".repeat(20),oracleCodeHash:"0x"+"56".repeat(32),verifierProxy:manifest.verifierProxy,verifierCodeHash:manifest.verifierCodeHash,maxReportBundleSize:5,registryVersion:9,authorizedConsumers:["0x"+"78".repeat(20)]};
return {manifest,record,actual:{...structuredClone(record),sequencer:manifest.sequencer,markets:manifest.markets}};}
test("deployment comparison detects owner market and consumer drift",()=>{const {manifest,record,actual}=fixture();assert.deepEqual(compareDeployment(manifest,record,actual),[]);
actual.owner="0x"+"99".repeat(20);actual.markets=structuredClone(actual.markets);actual.markets[0].streamDecimals=8;actual.authorizedConsumers=[];
assert.deepEqual(compareDeployment(manifest,record,actual),["owner","BTC_USD streamDecimals","consumer authorization"]);});

import {buildDeploymentRecord} from "./deployment-record.mjs";
test("deployment records bind a successful receipt to pinned configuration and consumers",()=>{
  const {manifest,record,actual}=fixture();actual.blockNumber=100n;
  const receipt={status:"success",transactionHash:"0x"+"ab".repeat(32),contractAddress:record.oracle,blockNumber:90n};
  const build=(changes={})=>buildDeploymentRecord({manifest,receipt:{...receipt,...changes},snapshot:actual,owner:record.owner,consumers:record.authorizedConsumers});
  assert.equal(build().deploymentBlock,90n);
  for(const changes of [{status:"reverted"},{blockNumber:101n},{blockNumber:0n},{contractAddress:record.owner},{transactionHash:"0x00"}])assert.throws(()=>build(changes));
  actual.owner=record.oracle;assert.throws(()=>build(),/state mismatch/);
});
