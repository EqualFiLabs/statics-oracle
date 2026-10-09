let requestId = 0;

export async function rpc(url, method, params = [], timeoutMs = 8_000) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++requestId, method, params }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.error) throw new Error(`RPC ${method} failed: ${payload.error.code}`);
  if (payload.result === undefined || payload.result === null) {
    throw new Error(`RPC ${method} returned no result`);
  }
  return payload.result;
}

export async function assertRpcChain(url, expectedChainId) {
    const chainId = BigInt(await rpc(url, "eth_chainId"));
  if (chainId !== BigInt(expectedChainId)) {
    throw new Error(`wrong chain ID: expected ${expectedChainId}, received ${chainId}`);
  }
}

export async function getBlock(url, block = "latest") {
  const tag = typeof block === "bigint" ? `0x${block.toString(16)}` : block;
  const value = await rpc(url, "eth_getBlockByNumber", [tag, false]);
  if (!value.hash || value.number === undefined || value.timestamp === undefined) {
    throw new Error("RPC returned an incomplete block");
  }
  return {
    number: BigInt(value.number),
    hash: String(value.hash).toLowerCase(),
    timestamp: BigInt(value.timestamp),
  };
}

export async function waitForBlock(url, blockNumber, timeoutMs = 6_000) {
  const deadline = Date.now() + timeoutMs;
  do {
    try {
      return await getBlock(url, blockNumber);
    } catch (error) {
      if (Date.now() >= deadline) throw error;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  } while (Date.now() < deadline);
  throw new Error("reference RPC did not publish the sequencer-feed block");
}

export function parseSequencerFeedMessage(data) {
  const payload = JSON.parse(String(data));
  const messages = payload.version === 1 && Array.isArray(payload.messages)
    ? payload.messages
    : [];
  const message = [...messages].reverse().find((value) =>
    value?.sequenceNumber !== undefined &&
    /^0x[0-9a-fA-F]{64}$/.test(String(value?.blockHash)) &&
    value?.message?.message?.header?.timestamp !== undefined
  );
  if (!message) throw new Error("sequencer feed returned no usable block");
  return {
    number: BigInt(message.sequenceNumber),
    hash: String(message.blockHash).toLowerCase(),
    timestamp: BigInt(message.message.message.header.timestamp),
  };
}

export async function readSequencerFeedHead(url, timeoutMs = 8_000) {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    let settled = false;
    const finish = (result, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      socket.onerror = null;
      socket.onmessage = null;
      try { socket.close(); } catch { /* already closed */ }
      result(value);
    };
    const timeout = setTimeout(() => finish(reject, new Error("sequencer feed timed out")), timeoutMs);
    socket.onerror = () => finish(reject, new Error("sequencer feed connection failed"));
    socket.onmessage = (event) => {
      try {
        finish(resolve, parseSequencerFeedMessage(event.data));
      } catch (error) {
        finish(reject, error instanceof Error ? error : new Error("invalid sequencer feed message"));
      }
    };
  });
}
