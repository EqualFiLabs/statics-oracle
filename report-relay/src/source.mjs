import { createClient } from "@chainlink/data-streams-sdk";
import { readCredentials } from "./auth.mjs";
const silent=Object.freeze({debug(){},info(){},warn(){},error(){}});
/** Credentials and the SDK remain private to this transport; raw errors never leave it. */
export function createSource({env=process.env,chainId,clientFactory=createClient}) {
  const client=clientFactory({...readCredentials(env,chainId),timeout:10000,retryAttempts:1,retryDelay:1000,wsAllowOutOfOrder:true,logging:{logger:silent}});
  let stream;let allowed=new Set();
  return {
    async start(ids,onReport,onStatus) {
      if(stream)throw new Error("source already started");allowed=new Set(ids.map(x=>x.toLowerCase()));
      stream=client.createStream([...allowed],{maxReconnectAttempts:100,reconnectInterval:1000});
      stream.on("report",report=>{if(allowed.has(report?.feedID?.toLowerCase()))onReport(report);else onStatus("unsupported-report");});
      stream.on("error",()=>onStatus("upstream-error"));
      stream.on("disconnected",()=>onStatus("disconnected"));
      stream.on("reconnecting",()=>onStatus("reconnecting"));
      stream.on("connection-restored",()=>onStatus("connected"));
      await stream.connect();onStatus("connected");
    },
    async page(id,start,limit) {
      if(!allowed.has(id.toLowerCase())||!Number.isSafeInteger(start)||start<0||!Number.isSafeInteger(limit)||limit<1||limit>1000)throw new Error("invalid recovery request");
      try{return await client.getReportsPage(id,start,limit);}catch{throw new Error("report recovery unavailable");}
    },
    async close(){if(stream){await stream.close();stream=undefined;}allowed.clear();}
  };
}
