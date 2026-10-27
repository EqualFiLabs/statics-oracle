import test from "node:test";
import assert from "node:assert/strict";
import {EventEmitter} from "node:events";
import {createSource} from "../src/source.mjs";
import {Relay} from "../src/relay.mjs";
import {report,config,streamId} from "../support/fixtures.mjs";
import {serve,token} from "../support/http.mjs";
test("SDK transport through HTTP preserves the exact full report bytes",async t=>{
  const stream=new EventEmitter();stream.connect=async()=>{};stream.close=async()=>{};
  const env={DATA_STREAMS_API_KEY:"fixture-key",DATA_STREAMS_API_SECRET:"fixture-secret"};
  const source=createSource({env,chainId:4663,clientFactory:()=>({createStream:()=>stream,getReportsPage:async()=>[]})});
  const relay=new Relay({source,config,clock:()=>1000});await relay.start();t.after(()=>relay.stop());
  const first=report({upper:true});const second=report({from:991,observed:991});
  // Upstream metadata cannot replace fields decoded from the opaque report body.
  stream.emit("report",{...second,price:"999999",observationsTimestamp:0});stream.emit("report",first);
  stream.emit("report",{feedID:3});
  const request=await serve(t,relay);const response=await request({marketId:"BTC-USD"});assert.equal(response.status,200);
  const payload=await response.json();assert.deepEqual(payload,{marketId:"BTC-USD",streamId,reports:[first.fullReport,second.fullReport],servedAt:1000});
  const serialized=JSON.stringify(payload);for(const secret of [...Object.values(env),token])assert.equal(serialized.includes(secret),false);
  assert.equal(Object.hasOwn(payload,"price"),false);assert.equal(Object.hasOwn(payload,"signature"),false);
  assert.equal(response.headers.get("cache-control"),"no-store");assert.equal(response.headers.get("access-control-allow-origin"),null);
});
test("configured metadata cannot smuggle a different stream body",async t=>{
  const stream=new EventEmitter();stream.connect=async()=>{};stream.close=async()=>{};
  const source=createSource({env:{DATA_STREAMS_API_KEY:"fixture",DATA_STREAMS_API_SECRET:"fixture"},chainId:4663,clientFactory:()=>({createStream:()=>stream,getReportsPage:async()=>[]})});
  const relay=new Relay({source,config,clock:()=>1000});await relay.start();t.after(()=>relay.stop());
  stream.emit("report",{...report({id:"0x0003"+"cd".repeat(30)}),feedID:streamId});
  assert.equal(relay.health().markets["BTC-USD"].rejected,1);const request=await serve(t,relay);
  assert.equal((await request({marketId:"BTC-USD"})).status,503);
});
