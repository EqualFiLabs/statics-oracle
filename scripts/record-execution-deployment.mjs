#!/usr/bin/env node
import {readFileSync,writeFileSync} from "node:fs";
import {readManifest} from "./execution/manifest.mjs";
import {readExecutionState} from "./execution/rpc-state.mjs";
import {buildDeploymentRecord} from "./execution/deployment-record.mjs";
async function main(){
 const options={};const args=process.argv.slice(2);
 for(let i=0;i<args.length;i+=2){if(!["--manifest","--receipt","--block","--owner","--consumers","--output"].includes(args[i])||!args[i+1])throw new Error("invalid arguments");options[args[i]]=args[i+1];}
 for(const key of ["--manifest","--receipt","--block","--owner","--consumers","--output"])if(!options[key])throw new Error("missing record argument");
 const manifest=readManifest(options["--manifest"],{deployable:true});const receipt=JSON.parse(readFileSync(options["--receipt"],"utf8"));
 const consumers=options["--consumers"].split(",");const snapshot=await readExecutionState({manifest,oracle:receipt.contractAddress,consumers,blockNumber:BigInt(options["--block"])});
 const record=buildDeploymentRecord({manifest,receipt,snapshot,owner:options["--owner"],consumers});
 writeFileSync(options["--output"],JSON.stringify(record,(_,v)=>typeof v==="bigint"?v.toString():v,2)+"\n",{flag:"wx",mode:0o600});
 console.log("deployment record created from receipt and pinned state");
}
main().catch(()=>{console.error("deployment record failed; verify arguments, receipt and pinned state");process.exitCode=1;});
