// Unsigned ABI fixtures exercise transport only; they cannot pass the onchain verifier.
export const streamId="0x0003"+"ab".repeat(30);
export const market={label:"BTC-USD",streamId,executionDelay:10,maxReportWindow:30};
const word=value=>BigInt.asUintN(256,BigInt(value)).toString(16).padStart(64,"0");
export function report({from=990,observed=990,expires=1100,price=100n,id=streamId,nonce=0,upper=false}={}) {
  const body=id.slice(2)+[from,observed,0,0,expires,price,price-1n,price+1n].map(word).join("");
  const fullReport="0x"+[nonce,0,0,224,544,576,0,288].map(word).join("")+body+word(0)+word(0);
  return {feedID:id,fullReport:upper?"0x"+fullReport.slice(2).toUpperCase():fullReport};
}
export function fakeSource(pages=[]) {
  return {calls:[],async start(ids,onReport,onStatus){this.ids=ids;this.emit=onReport;this.status=onStatus;},
    async page(...args){this.calls.push(args);return typeof pages==="function"?pages(...args):pages.shift()??[];},async close(){this.closed=true;}};
}
export const config={markets:[market],bufferDepth:8,bundleSize:2,recoveryLimit:4,maxReportBytes:65536};
