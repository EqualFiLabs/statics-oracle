import {createRequire} from "node:module";
const require=createRequire(new URL("../../observer/package.json",import.meta.url));
export async function readExecutionState({manifest,oracle,consumers,blockNumber,env=process.env}) {
  const {createPublicClient,http,parseAbi,keccak256,isAddress}=require("viem");
  if(!isAddress(oracle)||!Array.isArray(consumers)||consumers.some(x=>!isAddress(x)))throw new Error("invalid deployment addresses");
  const url=env[manifest.chainId===4663?"ROBINHOOD_MAINNET":"ROBINHOOD_TESTNET"];if(!url)throw new Error("configured Robinhood RPC required");
  const client=createPublicClient({transport:http(url,{retryCount:0,timeout:15000})});
  const chainId=await client.getChainId();if(chainId!==manifest.chainId)throw new Error("wrong execution chain");
  const block=await client.getBlock({blockNumber});
  const abi=parseAbi(["function owner() view returns (address)","function verifierProxy() view returns (address)","function maxReportBundleSize() view returns (uint8)","function registryVersion() view returns (uint64)","function sequencerConfig() view returns ((address feed,uint32 gracePeriod))","function marketConfig(bytes32) view returns ((bytes32 streamId,uint32 executionDelay,uint32 maxReportWindow,uint8 streamDecimals,uint8 status))","function isAuthorizedConsumer(address) view returns (bool)"]);
  const read=(functionName,args=[])=>client.readContract({address:oracle,abi,functionName,args,blockNumber});
  const codeHash=async address=>{const code=await client.getCode({address,blockNumber});if(!code||code==="0x")throw new Error("missing deployment code");return keccak256(code);};
  const sequencer=await read("sequencerConfig");
  const actual={chainId,oracle,blockNumber:block.number,blockHash:block.hash,blockTimestamp:block.timestamp,owner:await read("owner"),oracleCodeHash:await codeHash(oracle),verifierProxy:await read("verifierProxy"),maxReportBundleSize:await read("maxReportBundleSize"),registryVersion:await read("registryVersion"),sequencer:{...sequencer,codeHash:await codeHash(sequencer.feed)},markets:[],authorizedConsumers:[]};
  actual.verifierCodeHash=await codeHash(actual.verifierProxy);
  for(const row of manifest.markets){const got=await read("marketConfig",[row.marketId]);actual.markets.push({...got,marketId:row.marketId,status:["UNSET","CANDIDATE","ENABLED","DISABLED"][got.status]});}
  for(const consumer of consumers)if(await read("isAuthorizedConsumer",[consumer]))actual.authorizedConsumers.push(consumer);
  return actual;
}
