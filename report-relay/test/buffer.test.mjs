import test from "node:test";
import assert from "node:assert/strict";
import {ReportBuffer,AvailabilityError} from "../src/buffer.mjs";
import {Relay} from "../src/relay.mjs";
import {market,report,fakeSource,config} from "../support/fixtures.mjs";
const buffer=(options={})=>new ReportBuffer({market,depth:4,clock:()=>1000,...options});
test("buffer accepts out of order reports, deduplicates bytes and evicts oldest",()=>{
  const b=buffer();const first=report();const later=report({from:991,observed:991});
  assert.equal(b.add(later),true);assert.equal(b.add(first),true);
  assert.equal(b.add({...first,fullReport:"0x"+first.fullReport.slice(2).toUpperCase()}),false);
  assert.deepEqual(b.bundle(2),[first.fullReport,later.fullReport]);
  for(let observed=992;observed<=994;observed++)b.add(report({from:observed,observed}));
  assert.equal(b.snapshot(2).reportCount,4);assert.equal(b.counters.evicted,1);assert.equal(b.counters.duplicates,1);
  assert.throws(()=>b.bundle(2),AvailabilityError);
});
test("bounds, overlap, gaps and invalid bodies fail closed",()=>{
  const b=buffer();
  for(const row of [report({price:0n}),report({observed:1001}),report({expires:999}),report({from:900,observed:990}),report({from:991,observed:990}),report({id:"0x0003"+"cd".repeat(30)}),{fullReport:"0x01"},{fullReport:"0x"+"ff".repeat(65537)}])assert.equal(b.add(row),false);
  b.add(report());b.add(report({from:992,observed:992}));assert.throws(()=>b.bundle(2),AvailabilityError);
  assert.throws(()=>b.bundle(4),AvailabilityError);assert.throws(()=>b.bundle(0),AvailabilityError);
  b.add(report({nonce:1}));assert.throws(()=>b.bundle(1),AvailabilityError);
  assert.equal(b.counters.rejected,8);
});
test("recovery backfills the delayed reference before following the live tail",()=>{
  const b=buffer();b.add(report({from:1000,observed:1000}));assert.equal(b.recoveryStart(),960);
  b.add(report());assert.equal(b.recoveryStart(),991);
});
test("reconnect recovers bounded pages and coalesces concurrent requests",async()=>{
  let release;let pending=false;const gate=new Promise(resolve=>release=resolve);
  const source=fakeSource(async()=>{if(pending)await gate;return [];});const relay=new Relay({source,config,clock:()=>1000});
  await relay.start();pending=true;source.calls.length=0;
  const one=relay.recover("BTC-USD");const two=relay.recover("BTC-USD");assert.equal(source.calls.length,1);release();await Promise.all([one,two]);
  pending=false;source.status("disconnected");assert.equal(relay.health().connected,false);
  source.status("reconnecting");source.status("connected");await relay.recoverAll();assert.equal(relay.health().reconnects,1);
  source.emit(report({from:991,observed:991}));source.emit(report());assert.equal(relay.reports("BTC-USD").reports.length,2);
  source.emit({feedID:12});assert.equal(relay.health().unsupportedReports,1);
  await relay.stop();assert.equal(source.closed,true);
});
