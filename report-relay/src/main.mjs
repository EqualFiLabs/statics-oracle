import { loadConfig } from "./config.mjs";
import { requestAuthorizer } from "./auth.mjs";
import { createSource } from "./source.mjs";
import { Relay } from "./relay.mjs";
import { createRelayServer } from "./server.mjs";
async function main(){
  const config=loadConfig();const authorize=requestAuthorizer(process.env);
  const source=createSource({chainId:config.manifest.chainId});
  const relay=new Relay({source,config,onStatus:event=>console.log(JSON.stringify({event}))});
  const server=createRelayServer({relay,authorize});
  let stopping=false;
  const stop=async()=>{if(stopping)return;stopping=true;server.close();await relay.stop();server.closeAllConnections();};
  process.once("SIGTERM",()=>void stop());process.once("SIGINT",()=>void stop());
  server.on("error",()=>{console.error("relay listener failed");void stop();process.exitCode=1;});
  await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(config.port,config.host,resolve);});
  try{await relay.start();}catch{await stop();throw new Error("relay startup failed");}
  console.log(JSON.stringify({event:"relay-started",mode:config.mode,markets:config.markets.length}));
}
main().catch(()=>{console.error("relay startup failed; check private configuration and upstream availability");process.exitCode=1;});
