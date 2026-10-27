#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { readExecutionState } from "./execution/rpc-state.mjs";
import { readManifest } from "./execution/manifest.mjs";
import { compareDeployment } from "./execution/deployed-state.mjs";
async function main(){
  const args=process.argv.slice(2);const opts={};
  for(let i=0;i<args.length;i+=2){if(!["--manifest","--record","--block"].includes(args[i])||!args[i+1])throw new Error("invalid arguments");opts[args[i]]=args[i+1];}
  const manifest=readManifest(opts["--manifest"]??"config/robinhood-mainnet.streams.json",{deployable:Boolean(opts["--record"])});
  if(!opts["--record"]){console.log("candidate stream manifest valid; deployment qualification pending");return;}
  const record=JSON.parse(readFileSync(opts["--record"],"utf8"));
  const block=BigInt(opts["--block"]??record.blockNumber);if(block<=0n)throw new Error("pinned block required");
  const actual=await readExecutionState({manifest,oracle:record.oracle,consumers:record.authorizedConsumers,blockNumber:block});
  const differences=compareDeployment(manifest,record,actual);if(differences.length)throw new Error(`deployment drift: ${differences.join(", ")}`);
  console.log(`reviewed deployment matches at block ${block}; consumer enumeration requires event-history review`);
}
main().catch(error=>{const safe=/^(invalid|candidate|unratified|unsupported|missing|configured|wrong|execution|deployment drift:|deprecated|testing)/.test(error.message)?error.message:"execution verification failed";console.error(safe);process.exitCode=1;});
