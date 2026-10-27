import test from "node:test";
import assert from "node:assert/strict";
import {Relay,AvailabilityError} from "../src/relay.mjs";
import {createSource} from "../src/source.mjs";
import {report,config,fakeSource,streamId} from "../support/fixtures.mjs";
import {serve} from "../support/http.mjs";
test("outage may serve still valid signed bytes but never stale or substituted prices",async t=>{
  let now=1000;const statuses=[];const source=fakeSource();const relay=new Relay({source,config,clock:()=>now,onStatus:s=>statuses.push(s)});
  await relay.start();t.after(()=>relay.stop());source.emit(report());source.emit(report({from:991,observed:991}));
  const request=await serve(t,relay);assert.equal((await request({marketId:"BTC-USD"})).status,200);
  source.page=async()=>{throw new Error("credential-secret-upstream-error");};source.status("disconnected");
  await relay.recoverAll();assert.equal((await request({marketId:"BTC-USD"})).status,200);
  now=1002;const failed=await request({marketId:"BTC-USD"});assert.equal(failed.status,503);assert.deepEqual(await failed.json(),{error:"availability_failure"});
  assert.equal(relay.health().ready,false);assert.ok(relay.health().recoveryFailures>0);assert.equal(JSON.stringify(statuses).includes("credential-secret"),false);
  source.page=async()=>[report({from:992,observed:992})];await relay.recoverAll();assert.equal((await request({marketId:"BTC-USD"})).status,200);
  now=1200;assert.throws(()=>relay.reports("BTC-USD"),AvailabilityError);
  await relay.stop();assert.throws(()=>relay.reports("BTC-USD"),AvailabilityError);
});
test("oversized recovery pages and repeated nonprogress cannot grow the buffer",async()=>{
  const source=fakeSource(()=>Array(5).fill(report()));const relay=new Relay({source,config,clock:()=>1000});await relay.start();
  assert.ok(relay.health().recoveryFailures>0);assert.equal(relay.health().markets["BTC-USD"].reportCount,0);
  source.page=async()=>Array(4).fill(report());source.calls.length=0;await relay.recoverAll();assert.equal(relay.health().markets["BTC-USD"].reportCount,1);assert.equal(relay.health().ready,false);
  await relay.stop();
});
test("transport sanitizes upstream exceptions",async()=>{
  const source=createSource({env:{DATA_STREAMS_API_KEY:"fixture",DATA_STREAMS_API_SECRET:"secret-fixture"},chainId:4663,clientFactory:()=>({createStream:()=>({on(){},async connect(){},async close(){}}),async getReportsPage(){throw new Error("secret-fixture");}})});
  await source.start([streamId],()=>{},()=>{});await assert.rejects(source.page(streamId,990,1),{message:"report recovery unavailable"});
  await assert.rejects(source.page("0x0003"+"cc".repeat(30),990,1),{message:"invalid recovery request"});await source.close();
});
test("stopping during asynchronous startup leaves the relay unavailable",async()=>{
  let release;const gate=new Promise(resolve=>release=resolve);const source=fakeSource();source.start=async()=>gate;
  const relay=new Relay({source,config});const starting=relay.start();await relay.stop();release();await starting;assert.equal(relay.health().ready,false);
});
