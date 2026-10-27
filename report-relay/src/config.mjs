import { readManifest } from "../../scripts/execution/manifest.mjs";
export function integer(value, name, min, max) {
  const number=Number(value);if(value===undefined||value===""||!Number.isSafeInteger(number)||number<min||number>max)throw new Error(`invalid ${name}`);return number;
}
export function loadConfig(env=process.env) {
  const mode=env.RELAY_MODE??"production";
  if(!["production","qualification"].includes(mode))throw new Error("invalid relay mode");
  const manifest=readManifest(env.EXECUTION_STREAM_MANIFEST??new URL("../../../config/robinhood-mainnet.streams.json",import.meta.url),{deployable:mode==="production"});
  const bundleSize=integer(env.RELAY_BUNDLE_SIZE??manifest.maxReportBundleSize,"bundle size",1,255);
  if(manifest.maxReportBundleSize!==null&&bundleSize>manifest.maxReportBundleSize)throw new Error("bundle exceeds reviewed bound");
  const bufferDepth=integer(env.RELAY_BUFFER_DEPTH??64,"buffer depth",bundleSize+1,4096);
  const markets=manifest.markets.filter(row=>row.status==="ENABLED"||(mode==="qualification"&&row.status==="CANDIDATE")).map(row=>({...row,
    executionDelay:row.executionDelay??integer(env.RELAY_QUALIFICATION_DELAY_SECONDS,"qualification delay",1,0xffffffff),
    maxReportWindow:row.maxReportWindow??integer(env.RELAY_QUALIFICATION_WINDOW_SECONDS,"qualification window",1,0xffffffff)}));
  if(!markets.length)throw new Error("no reviewed relay markets");
  return {mode,manifest,markets,bundleSize,bufferDepth,host:"127.0.0.1",port:integer(env.RELAY_PORT??8787,"relay port",1,65535),
    recoveryLimit:integer(env.RELAY_RECOVERY_LIMIT??128,"recovery limit",1,1000),maxReportBytes:65536};
}
