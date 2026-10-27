import {WORD,ADDRESS,validateManifest} from "./manifest.mjs";
import {compareDeployment} from "./deployed-state.mjs";
export function buildDeploymentRecord({manifest,receipt,snapshot,owner,consumers}) {
  validateManifest(manifest,{deployable:true});
  if(![1,"0x1","success"].includes(receipt.status)||!WORD.test(receipt.transactionHash)||!ADDRESS.test(receipt.contractAddress)||receipt.contractAddress.toLowerCase()!==snapshot.oracle.toLowerCase())throw new Error("invalid successful deployment receipt");
  const deployedBlock=BigInt(receipt.blockNumber);if(deployedBlock<=0n||deployedBlock>BigInt(snapshot.blockNumber))throw new Error("invalid deployment block");
  const expected={...snapshot,owner,authorizedConsumers:consumers};
  const differences=compareDeployment(manifest,expected,snapshot);if(differences.length)throw new Error("deployment record state mismatch");
  return {...snapshot,deploymentTransaction:receipt.transactionHash,deploymentBlock:deployedBlock,consumerEnumeration:"reviewed list only; verify full event history separately"};
}
