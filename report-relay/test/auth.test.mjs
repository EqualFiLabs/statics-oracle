import test from "node:test";
import assert from "node:assert/strict";
import {readCredentials,requestAuthorizer} from "../src/auth.mjs";
import {createSource} from "../src/source.mjs";
import {loadConfig,integer} from "../src/config.mjs";
const env={DATA_STREAMS_API_KEY:"fixture-key",DATA_STREAMS_API_SECRET:"fixture-secret",RELAY_ACCESS_TOKEN:"x".repeat(40)};
test("credentials stay inside the official transport",async()=>{
  for(const value of [{},{...env,DATA_STREAMS_API_KEY:" "},{...env,DATA_STREAMS_API_SECRET:""}])assert.throws(()=>readCredentials(value,4663));
  assert.throws(()=>readCredentials(env,1));
  let received;
  const source=createSource({env:{...env,DATA_STREAMS_ENDPOINT:"https://untrusted.invalid"},chainId:4663,clientFactory:config=>{received=config;return {};}});
  assert.equal(received.apiKey,env.DATA_STREAMS_API_KEY);assert.equal(received.userSecret,env.DATA_STREAMS_API_SECRET);
  assert.equal(received.endpoint,"https://api.dataengine.chain.link");assert.equal(received.wsEndpoint,"wss://ws.dataengine.chain.link");
  assert.equal(readCredentials(env,46630).endpoint,"https://api.testnet-dataengine.chain.link");
  assert.equal(JSON.stringify(source),"{}");assert.equal(received.wsAllowOutOfOrder,true);
  for(const method of ["debug","info","warn","error"])assert.doesNotThrow(()=>received.logging.logger[method](env));
});
test("backend bearer authorization rejects missing, malformed and wrong tokens",()=>{
  for(const token of [undefined,"short","x".repeat(40)+"\n"])assert.throws(()=>requestAuthorizer({RELAY_ACCESS_TOKEN:token}));
  const authorize=requestAuthorizer(env);
  for(const authorization of [undefined,"",env.RELAY_ACCESS_TOKEN,"Bearer wrong","bearer "+env.RELAY_ACCESS_TOKEN])assert.equal(authorize({headers:{authorization}}),false);
  assert.equal(authorize({headers:{authorization:"Bearer "+env.RELAY_ACCESS_TOKEN}}),true);
});
test("production refuses candidate parameters and qualification requires explicit bounded values",()=>{
  assert.throws(()=>loadConfig({}));
  const config={RELAY_MODE:"qualification",RELAY_BUNDLE_SIZE:"2",RELAY_QUALIFICATION_DELAY_SECONDS:"10",RELAY_QUALIFICATION_WINDOW_SECONDS:"30"};
  const loaded=loadConfig(config);assert.equal(loaded.markets.length,2);assert.equal(loaded.host,"127.0.0.1");assert.equal(loaded.bundleSize,2);
  for(const patch of [{RELAY_BUFFER_DEPTH:"2"},{RELAY_BUNDLE_SIZE:"256"},{RELAY_MODE:"other"},{RELAY_QUALIFICATION_DELAY_SECONDS:"0"},{RELAY_QUALIFICATION_WINDOW_SECONDS:"4294967296"}])assert.throws(()=>loadConfig({...config,...patch}));
  for(const value of [undefined,"",null,"1.5","Infinity","-1"])assert.throws(()=>integer(value,"fixture",1,255));
});
