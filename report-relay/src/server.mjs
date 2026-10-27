import { createServer } from "node:http";
import { AvailabilityError } from "./buffer.mjs";
function readBody(request) {
  return new Promise((resolve,reject)=>{let size=0;const chunks=[];let excessive=false;
    request.on("data",chunk=>{size+=chunk.length;if(size>1024)excessive=true;else chunks.push(chunk);});
    request.on("end",()=>{if(excessive){reject(Object.assign(new Error(),{status:413,code:"request_too_large"}));return;}
      try{resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));}catch{reject(Object.assign(new Error(),{status:400,code:"invalid_request"}));}});
    request.on("error",()=>reject(Object.assign(new Error(),{status:400,code:"invalid_request"})));
  });
}
export function createRelayServer({relay,authorize}) {
  const server=createServer({maxHeaderSize:8192},async(request,response)=>{
    const send=(status,body)=>{response.writeHead(status,{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff"});response.end(JSON.stringify(body));};
    if(!authorize(request)){send(401,{error:"unauthorized"});return;}
    if(request.url==="/v1/bucketperps/health"&&request.method==="GET") {const health=relay.health();send(health.ready?200:503,health);return;}
    if(request.url!=="/v1/bucketperps/execution-reports"||request.method!=="POST"){send(404,{error:"not_found"});return;}
    if(request.headers["content-type"]?.split(";")[0].trim()!=="application/json"){send(415,{error:"invalid_content_type"});return;}
    try {
      const body=await readBody(request);
      if(!body||Array.isArray(body)||Object.keys(body).length!==1||typeof body.marketId!=="string") {send(400,{error:"invalid_request"});return;}
      let result;
      try{result=relay.reports(body.marketId);}catch(error){if(error instanceof AvailabilityError)throw error;send(400,{error:"unsupported_market"});return;}
      send(200,result);
    }catch(error){if(error instanceof AvailabilityError)send(503,{error:"availability_failure"});else send(error.status??500,{error:error.code??"request_failed"});}
  });
  server.requestTimeout=5000;server.headersTimeout=5000;server.keepAliveTimeout=1000;server.maxRequestsPerSocket=100;
  return server;
}
