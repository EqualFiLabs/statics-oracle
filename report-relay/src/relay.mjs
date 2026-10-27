import { ReportBuffer, AvailabilityError } from "./buffer.mjs";
export class Relay {
  #source;#config;#clock;#buffers=new Map();#streams=new Map();#inflight=new Map();#timer;#stopped=true;
  constructor({source,config,clock=()=>Math.floor(Date.now()/1000),onStatus=()=>{}}) {
    this.#source=source;this.#config=config;this.#clock=clock;this.onStatus=onStatus;
    this.metrics={connected:false,reconnects:0,recoveryFailures:0,recoveries:0,unsupportedReports:0,lastStatus:"stopped"};
    for(const market of config.markets){
      this.#buffers.set(market.label,new ReportBuffer({market,depth:config.bufferDepth,maxReportBytes:config.maxReportBytes,clock}));
      const id=market.streamId.toLowerCase();const labels=this.#streams.get(id)??[];labels.push(market.label);this.#streams.set(id,labels);
    }
  }
  ingest(report) {
    if(this.#stopped)return;
    const labels=this.#streams.get(typeof report?.feedID==="string"?report.feedID.toLowerCase():undefined);if(!labels){++this.metrics.unsupportedReports;return;}
    for(const label of labels)this.#buffers.get(label).add(report);
  }
  async recover(label) {
    if(this.#stopped)return;
    if(this.#inflight.has(label))return this.#inflight.get(label);
    const market=this.#config.markets.find(row=>row.label===label);if(!market)throw new Error("unsupported recovery market");
    const work=(async()=>{
      let cursor=this.#buffers.get(label).recoveryStart(this.#clock());
      try {
        for(let page=0;page<4&&!this.#stopped;++page){
          const reports=await this.#source.page(market.streamId,cursor,this.#config.recoveryLimit);
          if(!Array.isArray(reports)||reports.length>this.#config.recoveryLimit)throw new Error();
          let next=cursor;
          for(const report of reports){this.ingest(report);
            // Only decoded bodies accepted by the buffer may advance its recovery cursor.
            next=Math.max(next,this.#buffers.get(label).recoveryStart(this.#clock()));
          }
          if(next<=cursor||reports.length<this.#config.recoveryLimit)break;cursor=next;
        }
        ++this.metrics.recoveries;
      }catch{++this.metrics.recoveryFailures;this.onStatus("recovery-unavailable");}
    })();
    this.#inflight.set(label,work);try{await work;}finally{this.#inflight.delete(label);}
  }
  async recoverAll(){await Promise.all(this.#config.markets.map(row=>this.recover(row.label)));}
  async start() {
    if(!this.#stopped)throw new Error("relay already started");this.#stopped=false;
    await this.#source.start([...this.#streams.keys()],report=>this.ingest(report),status=>{
      this.metrics.lastStatus=status;
      if(status==="connected"){this.metrics.connected=true;void this.recoverAll();}
      if(["disconnected","reconnecting","upstream-error"].includes(status))this.metrics.connected=false;
      if(status==="reconnecting")++this.metrics.reconnects;
      this.onStatus(status);
    });
    if(this.#stopped)return;await this.recoverAll();if(this.#stopped)return;this.#timer=setInterval(()=>void this.recoverAll(),10000);this.#timer.unref();
  }
  async stop(){this.#stopped=true;clearInterval(this.#timer);await this.#source.close();await Promise.allSettled([...this.#inflight.values()]);this.metrics.connected=false;}
  reports(label) {
    if(this.#stopped)throw new AvailabilityError();
    const buffer=this.#buffers.get(label);if(!buffer)throw new Error("unsupported market");
    const market=this.#config.markets.find(row=>row.label===label);const now=this.#clock();
    return {marketId:label,streamId:market.streamId,reports:buffer.bundle(this.#config.bundleSize,now),servedAt:now};
  }
  health(){const now=this.#clock();const markets=Object.fromEntries([...this.#buffers].map(([label,buffer])=>[label,buffer.snapshot(this.#config.bundleSize,now)]));
    return {ready:!this.#stopped&&Object.values(markets).every(row=>row.ready),...this.metrics,markets};}
}
export {AvailabilityError};
