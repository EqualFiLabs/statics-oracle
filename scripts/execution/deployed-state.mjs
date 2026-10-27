import { validateManifest } from "./manifest.mjs";
const same = (a,b) => String(a).toLowerCase() === String(b).toLowerCase();
export function compareDeployment(manifest,record,actual) {
  validateManifest(manifest,{ deployable:true });
  const differences=[];
  for(const field of ["chainId","oracle","owner","oracleCodeHash","verifierProxy","verifierCodeHash","maxReportBundleSize","registryVersion"])
    if(!same(record[field],actual[field])) differences.push(field);
  if(!same(actual.verifierProxy,manifest.verifierProxy)||!same(actual.verifierCodeHash,manifest.verifierCodeHash))differences.push("verifier binding");
  if(!same(actual.maxReportBundleSize,manifest.maxReportBundleSize))differences.push("bundle bound");
  for(const field of ["feed","codeHash","gracePeriod"])
    if(!same(actual.sequencer?.[field],manifest.sequencer?.[field]))differences.push(`sequencer ${field}`);
  for(const row of manifest.markets){
    const got=actual.markets?.find(x=>same(x.marketId,row.marketId));
    for(const field of ["streamId","executionDelay","maxReportWindow","streamDecimals","status"])
      if(!got || !same(got[field],row[field]))differences.push(`${row.label} ${field}`);
  }
  if(!Array.isArray(record.authorizedConsumers)||record.authorizedConsumers.length===0)differences.push("missing reviewed consumers");
  for(const consumer of record.authorizedConsumers??[])
    if(!actual.authorizedConsumers?.some(x=>same(x,consumer)))differences.push("consumer authorization");
  return differences;
}
