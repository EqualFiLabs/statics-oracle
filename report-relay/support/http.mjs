import {once} from "node:events";
import {createRelayServer} from "../src/server.mjs";
import {requestAuthorizer} from "../src/auth.mjs";
export const token="fixture-backend-token-".repeat(2);
export async function serve(t,relay){
  const server=createRelayServer({relay,authorize:requestAuthorizer({RELAY_ACCESS_TOKEN:token})});
  server.listen(0,"127.0.0.1");await once(server,"listening");
  t.after(async()=>{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));});
  const origin=`http://127.0.0.1:${server.address().port}`;
  return async(body,options={})=>fetch(origin+(options.path??"/v1/bucketperps/execution-reports"),{
    method:options.method??"POST",headers:{authorization:"Bearer "+token,"content-type":"application/json",...options.headers},
    body:(options.method??"POST")==="GET"?undefined:typeof body==="string"?body:JSON.stringify(body)});
}
