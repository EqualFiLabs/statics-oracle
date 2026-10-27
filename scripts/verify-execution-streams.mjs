#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { readManifest } from "./execution/manifest.mjs";
import { compareDeployment } from "./execution/deployed-state.mjs";
const require=createRequire(new URL("../observer/package.json",import.meta.url));
async function main(){
  const args=process.argv.slice(2);const opts={};
  for(let i=0;i<args.length;i+=2){if(!["--manifest","--record","--block"].includes(args[i])||!args[i+1])throw new Error("invalid arguments");opts[args[i]]=args[i+1];}
  const manifest=readManifest(opts["--manifest"]??"config/robinhood-mainnet.streams.json",{deployable:Boolean(opts["--record"])});
  if(!opts["--record"]){console.log("candidate stream manifest valid; deployment qualification pending");return;}
  const record=JSON.parse(readFileSync(opts["--record"],"utf8"));
  const block=BigInt(opts["--block"]??record.blockNumber);if(block<=0n)throw new Error("pinned block required");
  const {createPublicClient,http,parseAbi,keccak256,isAddress}=require("viem");
  if(!isAddress(record.oracle)||!isAddress(record.owner))throw new Error("invalid deployment record");
  const url=process.env[manifest.chainId===4663?"ROBINHOOD_MAINNET":"ROBINHOOD_TESTNET"];if(!url)throw new Error("configured Robinhood RPC required");
  const client=createPublicClient({transport:http(url,{retryCount:0,timeout:15000})});
  const chainId=await client.getChainId();if(chainId!==manifest.chainId)throw new Error("wrong execution chain");
  const abi=parseAbi(["function owner() view returns (address)","function verifierProxy() view returns (address)","function maxReportBundleSize() view returns (uint8)","function registryVersion() view returns (uint64)","function sequencerConfig() view returns ((address feed,uint32 gracePeriod))","function marketConfig(bytes32) view returns ((bytes32 streamId,uint32 executionDelay,uint32 maxReportWindow,uint8 streamDecimals,uint8 status))","function isAuthorizedConsumer(address) view returns (bool)"]);
  const read=(functionName,args=[])=>client.readContract({address:record.oracle,abi,functionName,args,blockNumber:block});
  const codeHash=async address=>{const code=await client.getCode({address,blockNumber:block});if(!code||code==="0x")throw new Error("missing deployment code");return keccak256(code);};
  const sequencer=await read("sequencerConfig");
  const actual={chainId,oracle:record.oracle,owner:await read("owner"),oracleCodeHash:await codeHash(record.oracle),verifierProxy:await read("verifierProxy"),maxReportBundleSize:await read("maxReportBundleSize"),registryVersion:await read("registryVersion"),sequencer:{...sequencer,codeHash:await codeHash(sequencer.feed)},markets:[],authorizedConsumers:[]};
  actual.verifierCodeHash=await codeHash(actual.verifierProxy);
  for(const row of manifest.markets){const got=await read("marketConfig",[row.marketId]);actual.markets.push({...got,marketId:row.marketId,status:["UNSET","CANDIDATE","ENABLED","DISABLED"][got.status]});}
  for(const consumer of record.authorizedConsumers??[])if(await read("isAuthorizedConsumer",[consumer]))actual.authorizedConsumers.push(consumer);
  const differences=compareDeployment(manifest,record,actual);if(differences.length)throw new Error(`deployment drift: ${differences.join(", ")}`);
  console.log(`reviewed deployment matches at block ${block}; consumer enumeration requires event-history review`);
}
main().catch(error=>{const safe=/^(invalid|candidate|unratified|unsupported|missing|configured|wrong|execution|deployment drift:|deprecated|testing)/.test(error.message)?error.message:"execution verification failed";console.error(safe);process.exitCode=1;});
