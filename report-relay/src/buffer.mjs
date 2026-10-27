import { createHash } from "node:crypto";
import { decodeReport } from "@chainlink/data-streams-sdk";
export class AvailabilityError extends Error {constructor(){super("signed reports unavailable");}}
const uint32=value=>Number.isSafeInteger(value)&&value>=0&&value<=0xffffffff;
export class ReportBuffer {
  #reports=[];#market;#depth;#maxBytes;#clock;
  constructor({market,depth,maxReportBytes=65536,clock=()=>Math.floor(Date.now()/1000)}) {
    if(!Number.isSafeInteger(depth)||depth<2||depth>4096)throw new Error("invalid report buffer depth");
    this.#market=market;this.#depth=depth;this.#maxBytes=maxReportBytes;this.#clock=clock;
    this.counters={accepted:0,duplicates:0,rejected:0,evicted:0};this.lastArrival=null;
  }
  add(report) {
    try {
      const fullReport=report?.fullReport;
      if(typeof fullReport!=="string"||!/^0x(?:[0-9a-fA-F]{2})+$/.test(fullReport)||(fullReport.length-2)/2>this.#maxBytes)throw new Error();
      const decoded=decodeReport(fullReport,this.#market.streamId);
      if(decoded.version!=="V3"||decoded.feedID.toLowerCase()!==this.#market.streamId.toLowerCase()||decoded.price<=0n)throw new Error();
      const {validFromTimestamp:from,observationsTimestamp:observed,expiresAt:expires}=decoded;const now=this.#clock();
      if(!uint32(from)||!uint32(observed)||!uint32(expires)||from>observed||observed>now||expires<now||observed-from>this.#market.maxReportWindow)throw new Error();
      const digest=createHash("sha256").update(fullReport.slice(2).toLowerCase()).digest("hex");
      if(this.#reports.some(item=>item.digest===digest)){++this.counters.duplicates;return false;}
      this.#reports=this.#reports.filter(item=>item.expires>=now);
      this.#reports.push({fullReport,from,observed,expires,digest});
      this.#reports.sort((a,b)=>a.observed-b.observed||a.from-b.from||a.digest.localeCompare(b.digest));
      while(this.#reports.length>this.#depth){this.#reports.shift();++this.counters.evicted;}
      ++this.counters.accepted;this.lastArrival=now;return true;
    }catch{++this.counters.rejected;return false;}
  }
  bundle(size,now=this.#clock()) {
    if(!Number.isSafeInteger(size)||size<1||size>=this.#depth)throw new AvailabilityError();
    const target=now-this.#market.executionDelay;
    const valid=this.#reports.filter(item=>item.expires>=now&&item.observed<=now);
    const matching=valid.filter(item=>item.from<=target&&target<=item.observed);
    if(matching.length!==1||valid.length<size)throw new AvailabilityError();
    const index=valid.indexOf(matching[0]);const begin=Math.min(index,valid.length-size);
    const selected=valid.slice(begin,begin+size);
    for(let i=1;i<selected.length;++i)if(selected[i].from!==selected[i-1].observed+1)throw new AvailabilityError();
    return selected.map(item=>item.fullReport);
  }
  recoveryStart(now=this.#clock()) {
    const floor=Math.max(0,now-this.#market.executionDelay-Math.min(this.#market.maxReportWindow,300));
    const current=this.#reports.filter(item=>item.observed>=floor);
    if(!current.some(item=>item.from<=now-this.#market.executionDelay&&now-this.#market.executionDelay<=item.observed))return floor;
    for(let i=1;i<current.length;++i)if(current[i].from>current[i-1].observed+1)return Math.max(floor,current[i-1].observed+1);
    return Math.max(floor,current.at(-1).observed+1);
  }
  snapshot(size,now=this.#clock()) {
    let ready=false;try{this.bundle(size,now);ready=true;}catch{}
    const latest=this.#reports.at(-1);let gaps=0;
    for(let i=1;i<this.#reports.length;++i)if(this.#reports[i].from>this.#reports[i-1].observed+1)++gaps;
    return {ready,reportCount:this.#reports.length,lastObservation:latest?.observed??null,
      observationLag:latest?Math.max(0,now-latest.observed):null,lastArrival:this.lastArrival,gaps,...this.counters};
  }
}
