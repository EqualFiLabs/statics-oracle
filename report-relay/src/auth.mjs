import { timingSafeEqual } from "node:crypto";
export function readCredentials(env,chainId) {
  const apiKey=env.DATA_STREAMS_API_KEY;const userSecret=env.DATA_STREAMS_API_SECRET;
  if(typeof apiKey!=="string"||!apiKey.trim()||typeof userSecret!=="string"||!userSecret.trim())throw new Error("Data Streams credentials required");
  const testnet=chainId===46630;if(!testnet&&chainId!==4663)throw new Error("unsupported subscription network");
  return {apiKey,userSecret,endpoint:testnet?"https://api.testnet-dataengine.chain.link":"https://api.dataengine.chain.link",
    wsEndpoint:testnet?"wss://ws.testnet-dataengine.chain.link":"wss://ws.dataengine.chain.link"};
}
export function requestAuthorizer(env) {
  const token=env.RELAY_ACCESS_TOKEN;
  if(typeof token!=="string"||token.length<32||/[\r\n]/.test(token))throw new Error("relay access token required");
  const expected=Buffer.from(`Bearer ${token}`);
  return request=>{const actual=Buffer.from(request.headers.authorization??"");return actual.length===expected.length&&timingSafeEqual(actual,expected);};
}
