#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const CHAIN_ID = 4663;
const L2_GATEWAY_ROUTER = "0x1E324B9316138CA9a73F960213621AD1aaf01B89";
export const SOURCES = Object.freeze({
  robinhoodAssets: "https://api.robinhood.com/rhj/assets",
  chainlinkDirectory:
    "https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json",
  robinhoodOracleDocs: "https://docs.robinhood.com/chain/oracles-and-price-feeds/",
  robinhoodNetworkDocs: "https://docs.robinhood.com/chain/connecting/",
  chainlinkEquityDocs:
    "https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood",
  chainlinkFeedCatalog: "https://docs.chain.link/data-feeds/price-feeds/addresses",
  robinhoodProtocolContracts: "https://docs.robinhood.com/chain/protocol-contracts/",
  chainlinkLinkTokenContracts: "https://docs.chain.link/resources/link-token-contracts",
});

export const REQUESTED_ASSETS = Object.freeze([
  ["AAPL", "STOCK", "0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9", "0x6B22A786bAa607d76728168703a39Ea9C99f2cD0", 18, "AAPL", "ENABLED"],
  ["AMD", "STOCK", "0x86923f96303D656E4aa86D9d42D1e57ad2023fdC", "0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72", 18, "AMD", "ENABLED"],
  ["AMZN", "STOCK", "0x12f190a9F9d7D37a250758b26824B97CE941bF54", "0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C", 18, "AMZN", "ENABLED"],
  ["ASML", "STOCK", "0x47F93d52cBeC7C6D2CfC080e154002370a60dAEA", "0xB4106147E8cce40b7d46124090d373A71b70f87D", 18, "ASML", "ENABLED"],
  ["BABA", "STOCK", "0xad25Ac6C84D497db898fa1E8387bf6Af3532a1c4", "0x62Cc8F9b5f56a33c9C8A60c8B92779f523c4E984", 18, "BABA", "ENABLED"],
  ["CLSK", "STOCK", "0xcBB95BBF36099d34dA091dc6Fa6F49EfA257Cee3", "0x810c12D3a554Bc47fd39597Fe3b3AAC4941F50eF", 18, "CLSK", "ENABLED"],
  ["COIN", "STOCK", "0x6330D8C3178a418788dF01a47479c0ce7CCF450b", "0xA3a468A452940B7D6b69991207B508c609a98Ef2", 18, "COIN", "ENABLED"],
  ["CRCL", "STOCK", "0xdF0992E440dD0be65BD8439b609d6D4366bf1CB5", "0x6652eDf64bA3731C4F2D3ce821A0Fb1f1f6b482a", 18, "CRCL", "ENABLED"],
  ["CRWV", "STOCK", "0x5f10A1C971B69e47e059e1dC91901B59b3fB49C3", "0xe1b3aABCAFAd1c94708dc1367dcfF8Aa4407487C", 18, "CRWV", "ENABLED"],
  ["DELL", "STOCK", "0x941AE714EC6D8130c7B75d67160Ca08f1e7d11Dd", "0x1C6c8cADBe02E19129c39dDB92281cE4c0bf206b", 18, "RHDELL", "ENABLED"],
  ["EURC", "STABLE", "0x697532723b423d38a6769ba2f804aec3faaf740b", "0xfF2B10c1973eD10c841434f98e456d8f3a0D7DD8", 6, "EURC", "ENABLED", "0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c"],
  ["EWY", "ETF", "0x7f0aBeF0C07280F82c6a08ead09dEd6BAE2C13Fc", "0xEFdf54610B62A7753Ec30bDc380847c12D32e1D1", 18, "EWY", "ENABLED"],
  ["GLD", "ETF", "0xC9a981FEE1F9DEc688bb123ccDeCc63D0deBFC4e", "0x470A51258068043bd43dC0a56245625C9fE86eB0", 18, "GLD", "ENABLED"],
  ["GME", "STOCK", "0x1b0E319c6A659F002271B69dB8A7df2F911c153E", "0x27C71df6A64fB476468EdF256CF72c038baB5B67", 18, "GME", "ENABLED"],
  ["GOOGL", "STOCK", "0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3", "0xF6f373a037c30F0e5010d854385cA89185AE638b", 18, "GOOGL", "ENABLED"],
  ["INTC", "STOCK", "0xc72b96e0E48ecd4DC75E1e45396e26300BC39681", "0x3f390C5C24628Ac7C489515402235FeAD71D1913", 18, "INTC", "ENABLED"],
  ["IONQ", "STOCK", "0x558378E000D634A36593E338eBacdd6207640EfE", "0x22EfeC4919baf55F360E0EDee4AbEB26DE4971eb", 18, "IONQ", "ENABLED"],
  ["LINK", "CRYPTO", "0x492641f648a4986844848e0befe66d14817bce34", "0xe86e3422Aa9B5e8ee9f3E41a63975bC387A8bce9", 18, "LINK", "ENABLED"],
  ["META", "STOCK", "0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35", "0x7C38C00C30BEe9378381E7B6135d7283356D71b1", 18, "META", "ENABLED"],
  ["MSFT", "STOCK", "0xe93237C50D904957Cf27E7B1133b510C669c2e74", "0x45C3C877C15E6BA2EBB19eA114Ea508d14C1Af2E", 18, "MSFT", "ENABLED"],
  ["MSTR", "STOCK", "0xec262a75e413fAfD0dF80480274532C79D42da09", "0x396118bdFB181e6240E74D243F266B061c0edc3D", 18, "MSTR", "ENABLED"],
  ["MU", "STOCK", "0xfF080c8ce2E5feadaCa0Da81314Ae59D232d4afD", "0x425EEFdCf05ed6526C3cE61Af99429A228a6d596", 18, "MU", "ENABLED"],
  ["NBIS", "STOCK", "0x9D9c6684F596F66a64C030B93A886D51Fd4D7931", "0xE1D87B116Ba0fe898998f1D140339D1fA1E09705", 18, "NBIS", "ENABLED"],
  ["NVDA", "STOCK", "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC", "0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15", 18, "NVDA", "ENABLED"],
  ["ORCL", "STOCK", "0xb0992820E760d836549ba69BC7598b4af75dEE03", "0x0e6a64a2B58A6693a531E6c555f3A5d042eEA844", 18, "ORCL", "ENABLED"],
  ["PLTR", "STOCK", "0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A", "0x820ABedFF239034956B7A9d2F0a331f9F075eB4c", 18, "PLTR", "ENABLED"],
  ["QQQ", "ETF", "0xD5f3879160bc7c32ebb4dC785F8a4F505888de68", "0x80901d846d5D7B030F26B480776EE3b29374C2ae", 18, "QQQ", "ENABLED"],
  ["RGTI", "STOCK", "0x284358abc07F9359f19f4b5b4aC91901Be2597Ba", "0x2A045cF1C49c61c166C036d2f06FA2D2d984f765", 18, "RGTI", "ENABLED"],
  ["RKLB", "STOCK", "0x3b14C39E89D60D627b42a1A4CA45b5bb45Fc12e2", "0x045477BF65Aef6f4F2386ad0164579e48381CC74", 18, "RKLB", "ENABLED"],
  ["SGOV", "ETF", "0x92FD66527192E3e61d4DDd13322Aa222DE86F9B5", "0xa0DF4ee0fFf975306345875E3548Fcc519577A11", 18, "RHSGOV", "ENABLED"],
  ["SLV", "ETF", "0x411eFb0E7f985935DAec3D4C3ebaEa0d0AD7D89f", "0x209b73908e92Ae021826eD79609845451Ecba2ce", 18, "SLV", "ENABLED"],
  ["SNDK", "STOCK", "0xB90A19fF0Af67f7779afF50A882A9CfF42446400", "0xfb133Fa4B7b385802B693a293606682Df47109A3", 18, "SNDK", "ENABLED"],
  ["SPCX", "STOCK", "0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa", "0xB265810950ba6c5C0Ff821c9963014a56fD8Bffb", 18, "SPCX", "ENABLED"],
  ["SPY", "ETF", "0x117cc2133c37B721F49dE2A7a74833232B3B4C0C", "0x319724394D3A0e3669269846abE664Cd621f9f6A", 18, "SPY", "ENABLED"],
  ["TSLA", "STOCK", "0x322F0929c4625eD5bAd873c95208D54E1c003b2d", "0x4A1166a659A55625345e9515b32adECea5547C38", 18, "TSLA", "ENABLED"],
  ["TSM", "STOCK", "0x58FfE4a942d3885bAa22D7520691F611EF09e7AA", "0x874cF94aa8eC88Fd9560094dD065f2fB3E41Fc2F", 18, "TSM", "ENABLED"],
  ["USAR", "STOCK", "0xd917B029C761D264c6A312BBbcDA868658eF86a6", "0xA994d3684e8400A6c8078226925779FdeE682DD9", 18, "RHUSAR", "ENABLED"],
  ["USDC", "STABLE", "0x80e0e24718dbFcad49ECAA6F1e6C89A190586cA8", "0x9e6f4605992a899eE2999999F3Ec80C41F452546", 6, "USDC", "ENABLED", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"],
  ["USDG", "STABLE", "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168", "0x61B7e5650328764B076A108EFF5fa7282a1B9aD2", 6, "USDG", "ENABLED"],
  ["USDS", "STABLE", "0x3830502883047dabc4ade46ef72e2bf9ab2d9b69", "0x2D88D75b625633dCcd65d9d53BfDD3Aea2d8e84f", 18, "USDS", "ENABLED", "0xdC035D45d973E3EC169d2276DDab16f1e407384F"],
  ["USDT", "STABLE", "0xE246BC49b0598d7Cd9f0eAD48B885034f1254380", "0xbf3550B6fAe1671da7C238Af12e03Ac586BEf3B1", 6, "USDT", "ENABLED", "0xdAC17F958D2ee523a2206206994597C13D831ec7"],
  ["USO", "ETF", "0xa30FA36Db767ad9eD3f7a60fC79526fB4d56D344", "0x75a9c76Ef439e2C7c2E5a34Ab105EcFe3766431c", 18, "USO", "ENABLED"],
  ["WBTC", "CRYPTO", "0x6bac06600D220Ac5Ac281AD1f504D2Cf0F90F6e6", "0x62107b0d3adA75fc1697fD342d99eed947a3aA5E", 8, "WBTC", "ENABLED", "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"],
  ["WETH", "CRYPTO", "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73", "0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9", 18, "ETH", "ENABLED"],
  ["cbBTC", "CRYPTO", "0xd3FCec4E6C6bF5D7369A912Dd52AB810F9b266d1", "0x0009cD492adf8167f9eEBf1293556A673530a21a", 8, "CBBTC", "ENABLED", "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf"],
  ["wstETH", "CRYPTO", "0xcD26A6AA5BB008240A998E242F51232FE98B12Cb", "0x3F5040B50FB37934573B210fE54B53a6F1A792E8", 18, "WSTETH", "ENABLED", "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"],
].map(([symbol, kind, token, feed, tokenDecimals, feedBase, status, l1Origin]) => ({
  symbol,
  kind,
  token,
  feed,
  tokenDecimals,
  feedBase,
  status,
  l1Origin,
})));

const SELECTORS = Object.freeze({
  decimals: "0x313ce567",
  description: "0x7284e416",
  latestRoundData: "0xfeaf968c",
  oraclePaused: "0x7706ba52",
  l1Address: "0xc2eeeebd",
  calculateL2TokenAddress: "0xa7e28d48",
});

function fail(message) {
  throw new Error(message);
}

function addressEqual(a, b) {
  return typeof a === "string" && typeof b === "string" && a.toLowerCase() === b.toLowerCase();
}

async function fetchJson(url, label) {
  const response = await fetch(url, { headers: { accept: "application/json" } });
  if (!response.ok) fail(`${label} returned HTTP ${response.status}`);
  try {
    return await response.json();
  } catch (error) {
    fail(`${label} returned malformed JSON: ${error.message}`);
  }
}

async function rpcRequest(rpcUrl, method, params) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  if (!response.ok) fail(`Robinhood RPC ${method} returned HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.error) fail(`Robinhood RPC ${method} failed: ${payload.error.message}`);
  return payload.result;
}

async function rpcBatch(rpcUrl, calls) {
  const results = new Map();
  for (let offset = 0; offset < calls.length; offset += 50) {
    const chunk = calls.slice(offset, offset + 50);
    const body = chunk.map((call, index) => ({
      jsonrpc: "2.0",
      id: offset + index + 1,
      method: call.method,
      params: call.params,
    }));
    const response = await fetch(rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!response.ok) fail(`Robinhood RPC batch returned HTTP ${response.status}`);
    const payload = await response.json();
    if (!Array.isArray(payload)) fail("Robinhood RPC returned a malformed batch response");
    for (const item of payload) {
      if (item.error) fail(`Robinhood RPC batch item failed: ${item.error.message}`);
      results.set(item.id, item.result);
    }
  }
  return calls.map((_, index) => {
    const id = index + 1;
    if (!results.has(id)) fail(`Robinhood RPC omitted batch response ${id}`);
    return results.get(id);
  });
}

function stripHex(value) {
  if (typeof value !== "string" || !value.startsWith("0x")) fail("Malformed hex RPC result");
  return value.slice(2);
}

function decodeUint(value, wordIndex = 0) {
  const hex = stripHex(value);
  const word = hex.slice(wordIndex * 64, (wordIndex + 1) * 64);
  if (word.length !== 64) fail("Short ABI uint result");
  return BigInt(`0x${word}`);
}

function decodeInt(value, wordIndex = 0) {
  const unsigned = decodeUint(value, wordIndex);
  return unsigned >= 2n ** 255n ? unsigned - 2n ** 256n : unsigned;
}

function decodeString(value) {
  const hex = stripHex(value);
  const offset = Number(decodeUint(value, 0));
  const lengthWordIndex = offset / 32;
  const length = Number(decodeUint(value, lengthWordIndex));
  const start = (lengthWordIndex + 1) * 64;
  const bytes = hex.slice(start, start + length * 2);
  if (bytes.length !== length * 2) fail("Short ABI string result");
  return Buffer.from(bytes, "hex").toString("utf8");
}

function keccakUtf8(value) {
  return execFileSync("cast", ["keccak", value], {
    encoding: "utf8",
    env: { ...process.env, FOUNDRY_DISABLE_NIGHTLY_WARNING: "true" },
  }).trim();
}

function parseArgs(argv) {
  const options = { output: "config/robinhood-mainnet.assets.json" };
  for (let i = 0; i < argv.length; ++i) {
    const arg = argv[i];
    if (arg === "--output") options.output = argv[++i];
    else if (arg === "--block") options.block = Number(argv[++i]);
    else if (arg === "--generated-at") options.generatedAt = argv[++i];
    else fail(`Unknown argument: ${arg}`);
  }
  if (!options.output) fail("--output requires a path");
  if (options.block !== undefined && (!Number.isSafeInteger(options.block) || options.block < 0)) {
    fail("--block must be a non-negative safe integer");
  }
  if (options.generatedAt && Number.isNaN(Date.parse(options.generatedAt))) {
    fail("--generated-at must be an ISO-8601 timestamp");
  }
  return options;
}

function requireUnique(items, description) {
  if (items.length !== 1) fail(`${description}: expected exactly one match, found ${items.length}`);
  return items[0];
}

export async function generateManifest({ rpcUrl, blockNumber, generatedAt }) {
  if (!rpcUrl) fail("ROBINHOOD_MAINNET is required");

  const [robinhoodPayload, chainlinkDirectory, chainIdHex, latestBlockHex] = await Promise.all([
    fetchJson(SOURCES.robinhoodAssets, "Robinhood asset registry"),
    fetchJson(SOURCES.chainlinkDirectory, "Chainlink feed directory"),
    rpcRequest(rpcUrl, "eth_chainId", []),
    rpcRequest(rpcUrl, "eth_blockNumber", []),
  ]);
  if (!Array.isArray(robinhoodPayload?.assets)) fail("Robinhood registry is missing assets[]");
  if (!Array.isArray(chainlinkDirectory)) fail("Chainlink directory must be an array");
  const chainId = Number(BigInt(chainIdHex));
  if (chainId !== CHAIN_ID) fail(`Wrong RPC chain ID: expected ${CHAIN_ID}, received ${chainId}`);

  const latestBlock = Number(BigInt(latestBlockHex));
  const verifiedBlock = blockNumber ?? latestBlock;
  if (verifiedBlock > latestBlock) fail(`Requested future block ${verifiedBlock}`);
  const blockTag = `0x${verifiedBlock.toString(16)}`;
  const block = await rpcRequest(rpcUrl, "eth_getBlockByNumber", [blockTag, false]);
  if (!block) fail(`Robinhood RPC could not load block ${verifiedBlock}`);
  const blockTimestamp = Number(BigInt(block.timestamp));
  const verifiedBlockTimestamp = new Date(blockTimestamp * 1000).toISOString();
  const verificationTimestamp = generatedAt ?? new Date().toISOString();

  const resolved = REQUESTED_ASSETS.map((requested) => {
    const feedMatches = chainlinkDirectory.filter((item) => addressEqual(item.proxyAddress, requested.feed));
    const feedSource = requireUnique(feedMatches, `${requested.symbol} Chainlink proxy`);
    if (feedSource.decimals !== 8) fail(`${requested.symbol} directory feed decimals are not 8`);
    if (!Number.isInteger(feedSource.heartbeat) || feedSource.heartbeat <= 0) {
      fail(`${requested.symbol} directory heartbeat is missing or invalid`);
    }
    if (feedSource.docs?.baseAsset !== requested.feedBase &&
        feedSource.docs?.baseAssetEntityId !== `crypto-${requested.feedBase}`) {
      fail(`${requested.symbol} Chainlink base identity mismatch`);
    }

    let robinhoodSource = null;
    if (requested.kind === "STOCK" || requested.kind === "ETF") {
      const tokenMatches = robinhoodPayload.assets.filter((asset) =>
        asset.deployments?.some(
          (deployment) => deployment.chainId === CHAIN_ID && addressEqual(deployment.contractAddress, requested.token),
        ),
      );
      robinhoodSource = requireUnique(tokenMatches, `${requested.symbol} Robinhood token`);
      if (robinhoodSource.tokenSymbol !== requested.symbol) fail(`${requested.symbol} Robinhood symbol mismatch`);
      if (robinhoodSource.tokenDecimals !== requested.tokenDecimals) fail(`${requested.symbol} Robinhood decimals mismatch`);
      if (robinhoodSource.status !== "ASSET_STATUS_ACTIVE") fail(`${requested.symbol} is not active in Robinhood registry`);
    }
    return { requested, feedSource, robinhoodSource };
  });

  const calls = [];
  for (const { requested } of resolved) {
    calls.push({ method: "eth_getCode", params: [requested.token, blockTag] });
    calls.push({ method: "eth_getCode", params: [requested.feed, blockTag] });
    calls.push({ method: "eth_call", params: [{ to: requested.token, data: SELECTORS.decimals }, blockTag] });
    calls.push({ method: "eth_call", params: [{ to: requested.feed, data: SELECTORS.decimals }, blockTag] });
    calls.push({ method: "eth_call", params: [{ to: requested.feed, data: SELECTORS.description }, blockTag] });
    calls.push({ method: "eth_call", params: [{ to: requested.feed, data: SELECTORS.latestRoundData }, blockTag] });
    if (requested.kind === "STOCK" || requested.kind === "ETF") {
      calls.push({ method: "eth_call", params: [{ to: requested.token, data: SELECTORS.oraclePaused }, blockTag] });
    }
    if (requested.l1Origin) {
      calls.push({ method: "eth_call", params: [{ to: requested.token, data: SELECTORS.l1Address }, blockTag] });
      calls.push({ method: "eth_call", params: [{
        to: L2_GATEWAY_ROUTER,
        data: `${SELECTORS.calculateL2TokenAddress}${requested.l1Origin.slice(2).padStart(64, "0")}`,
      }, blockTag] });
    }
  }
  const callResults = await rpcBatch(rpcUrl, calls);
  let cursor = 0;
  const assets = resolved.map(({ requested, feedSource, robinhoodSource }) => {
    const tokenCode = callResults[cursor++];
    const feedCode = callResults[cursor++];
    const tokenDecimals = Number(decodeUint(callResults[cursor++]));
    const feedDecimals = Number(decodeUint(callResults[cursor++]));
    const feedDescription = decodeString(callResults[cursor++]);
    const roundResult = callResults[cursor++];
    const roundId = decodeUint(roundResult, 0);
    const answer = decodeInt(roundResult, 1);
    const updatedAt = decodeUint(roundResult, 3);
    const answeredInRound = decodeUint(roundResult, 4);
    let stockOraclePaused = null;
    if (requested.kind === "STOCK" || requested.kind === "ETF") {
      stockOraclePaused = decodeUint(callResults[cursor++]) !== 0n;
    }

    if (requested.l1Origin) {
      const actualL1Origin = `0x${stripHex(callResults[cursor++]).slice(-40)}`;
      const canonicalL2 = `0x${stripHex(callResults[cursor++]).slice(-40)}`;
      if (!addressEqual(actualL1Origin, requested.l1Origin)) {
        fail(`${requested.symbol} bridge token L1 origin mismatch`);
      }
      if (!addressEqual(canonicalL2, requested.token)) {
        fail(`${requested.symbol} token does not match the canonical bridge address`);
      }
    }

    if (tokenCode === "0x") fail(`${requested.symbol} token has no code at block ${verifiedBlock}`);
    if (feedCode === "0x") fail(`${requested.symbol} feed has no code at block ${verifiedBlock}`);
    if (tokenDecimals !== requested.tokenDecimals) fail(`${requested.symbol} live token decimals mismatch`);
    if (feedDecimals !== feedSource.decimals) fail(`${requested.symbol} live feed decimals mismatch`);
    if (answer <= 0n) fail(`${requested.symbol} latest feed answer is not positive`);
    if (updatedAt === 0n || answeredInRound < roundId) fail(`${requested.symbol} latest feed round is incomplete`);
    if (updatedAt > BigInt(blockTimestamp)) fail(`${requested.symbol} latest feed timestamp is in the future`);
    if (BigInt(blockTimestamp) - updatedAt > BigInt(feedSource.heartbeat)) {
      fail(`${requested.symbol} latest feed round exceeds the published heartbeat`);
    }
    if (stockOraclePaused) fail(`${requested.symbol} stock oracle is paused at block ${verifiedBlock}`);

    return {
      symbol: requested.symbol,
      kind: requested.kind,
      status: requested.status,
      token: requested.token,
      feed: requested.feed,
      tokenDecimals,
      feedDecimals,
      feedDescription,
      feedDescriptionHash: keccakUtf8(feedDescription),
      chainlinkDirectoryName: feedSource.name,
      heartbeat: feedSource.heartbeat,
      maxAge: feedSource.heartbeat,
      maxAgePolicy: "CHAINLINK_DIRECTORY_HEARTBEAT",
      checkOraclePause: requested.kind === "STOCK" || requested.kind === "ETF",
      l1Origin: requested.l1Origin ?? null,
      verification: {
        verifiedAt: verificationTimestamp,
        verifiedBlock,
        verifiedBlockTimestamp,
        robinhoodAssetMatched: robinhoodSource === null ? null : true,
        robinhoodAssetId: robinhoodSource?.id ?? null,
        chainlinkFeedMatched: true,
        tokenCodeVerified: true,
        feedCodeVerified: true,
        tokenDecimalsVerified: true,
        feedDecimalsVerified: true,
        feedDescriptionVerified: true,
        latestAnswerPositive: true,
        roundComplete: true,
        timestampValid: true,
        freshnessWithinMaxAge: true,
        stockOraclePaused,
        bridgeOriginVerified: requested.l1Origin ? true : null,
        bridgeAddressVerified: requested.l1Origin ? true : null,
        roundId: roundId.toString(),
        updatedAt: Number(updatedAt),
      },
    };
  });
  assets.sort((a, b) => Buffer.from(a.symbol).compare(Buffer.from(b.symbol)));

  return {
    schemaVersion: 1,
    chainId: CHAIN_ID,
    quoteCurrency: "USD",
    generatedAt: verificationTimestamp,
    verifiedBlock,
    verifiedBlockTimestamp,
    sources: SOURCES,
    sequencer: {
      feed: "0xeCe3F60De85705472292a44787123a8Fc46CDa54",
      l1Reporter: "0x30adfaef118acaa415d73a20d55dc7a8cd3381b4",
      l1Inbox: "0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D",
      observerSetHash: "0x04d01fb3f628cf7fd0130982d87c1ba682525ffe923c6fc229ae0de25a388552",
      threshold: 2,
      pollIntervalSeconds: 30,
      failureSamples: 3,
      recoverySamples: 3,
      heartbeatIntervalSeconds: 300,
      leaseSeconds: 900,
      gracePeriod: null,
      verified: false,
      blocker: "Sequencer signal is deployed; independent review and recovery grace period remain pending",
    },
    policy: {
      maxAge: "Each row uses the heartbeat published for its exact proxy in the Chainlink directory",
      lifecycleStatus: "Desired reviewed configuration; not evidence that a contract is deployed or configured",
    },
    assetCount: assets.length,
    assets,
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const manifest = await generateManifest({
    rpcUrl: process.env.ROBINHOOD_MAINNET,
    blockNumber: options.block,
    generatedAt: options.generatedAt,
  });
  const output = `${JSON.stringify(manifest, null, 2)}\n`;
  if (options.output === "-") process.stdout.write(output);
  else writeFileSync(options.output, output, { encoding: "utf8" });
  process.stderr.write(`verified ${manifest.assets.length} assets at Robinhood block ${manifest.verifiedBlock}\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    process.stderr.write(`generate-whitelist: ${error.message}\n`);
    process.exitCode = 1;
  });
}
