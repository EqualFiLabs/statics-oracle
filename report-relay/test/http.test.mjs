import test from "node:test";
import assert from "node:assert/strict";
import {serve} from "../support/http.mjs";
test("HTTP accepts only configured market labels and the narrow request schema",async t=>{
  let calls=0;const request=await serve(t,{reports(label){++calls;if(label!=="BTC-USD")throw new Error();return {reports:[]};},health(){return {ready:false};}});
  for(const marketId of ["ETH-UNKNOWN","0x0003"+"ff".repeat(30),"__proto__",""])assert.equal((await request({marketId})).status,400);
  assert.equal(calls,4);
  for(const body of [{marketId:"BTC-USD",timestamp:990},{marketId:"BTC-USD",feedId:"arbitrary"},{marketId:"BTC-USD",bundleSize:200},[],null,{marketId:3},"{"]){assert.equal((await request(body)).status,400);}
  assert.equal(calls,4);assert.equal((await request({marketId:"BTC-USD"})).status,200);
  assert.equal((await request({marketId:"BTC-USD"},{headers:{authorization:"wrong"}})).status,401);
  assert.equal((await request({marketId:"BTC-USD"},{headers:{"content-type":"text/plain"}})).status,415);
  assert.equal((await request("x".repeat(1025))).status,413);
  assert.equal((await request(null,{method:"GET"})).status,404);
  assert.equal((await request(null,{method:"GET",path:"/v1/bucketperps/health"})).status,503);
  assert.equal((await request({marketId:"BTC-USD"},{path:"/v1/bucketperps/execution-reports?timestamp=990"})).status,404);
});
