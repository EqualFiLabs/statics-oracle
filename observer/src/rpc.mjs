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

// A service holds one feed connection and reads the most recent pushed head.
// Recoverable failures permit at most three connections per hour, spaced five
// minutes apart. Invalid feed data remains terminal until operator review.
export function createSequencerFeedReader(url, {
  WebSocketClass = WebSocket,
  firstMessageTimeoutMs = 8_000,
  maxMessageAgeMs = 60_000,
  reconnectDelayMs = 5 * 60_000,
  connectionWindowMs = 60 * 60_000,
  maxConnectionsPerWindow = 3,
  now = Date.now,
} = {}) {
  let socket;
  let latestHead;
  let receivedAt;
  let terminalError;
  let firstHeadPromise;
  let resolveFirstHead;
  let rejectFirstHead;
  let firstMessageTimeout;
  let recoverableError = false;
  let nextConnectAt = 0;
  let connectionAttempts = [];

  function fail(error, recoverable = true) {
    if (terminalError) return;
    terminalError = error;
    recoverableError = recoverable;
    nextConnectAt = now() + reconnectDelayMs;
    clearTimeout(firstMessageTimeout);
    if (socket) {
      socket.onmessage = null;
      socket.onerror = null;
      socket.onclose = null;
      try { socket.close(); } catch { /* already closed */ }
    }
    rejectFirstHead?.(error);
  }

  function start() {
    if (firstHeadPromise && !terminalError) return;
    const currentTime = now();
    if (terminalError && (!recoverableError || currentTime < nextConnectAt)) return;
    connectionAttempts = connectionAttempts.filter((attempt) => currentTime - attempt < connectionWindowMs);
    if (connectionAttempts.length >= maxConnectionsPerWindow) return;
    terminalError = undefined;
    recoverableError = false;
    receivedAt = undefined;
    firstHeadPromise = new Promise((resolve, reject) => {
      resolveFirstHead = resolve;
      rejectFirstHead = reject;
    });
    connectionAttempts.push(currentTime);
    try {
      socket = new WebSocketClass(url);
    } catch {
      fail(new Error("sequencer feed connection failed"));
      return;
    }
    firstMessageTimeout = setTimeout(
      () => fail(new Error("sequencer feed timed out")),
      firstMessageTimeoutMs,
    );
    socket.onerror = () => fail(new Error("sequencer feed connection failed"));
    socket.onclose = () => fail(new Error("sequencer feed connection closed"));
    socket.onmessage = (event) => {
      let head;
      try {
        head = parseSequencerFeedMessage(event.data);
      } catch (error) {
        if (error instanceof SyntaxError) fail(new Error("invalid sequencer feed message"), false);
        // Confirmation-only frames contain no head and are not samples.
        return;
      }
      if (latestHead && head.number < latestHead.number) return;
      if (latestHead && head.number === latestHead.number && head.hash !== latestHead.hash) {
        fail(new Error("sequencer feed reported conflicting block hashes"), false);
        return;
      }
      latestHead = head;
      receivedAt = now();
      clearTimeout(firstMessageTimeout);
      resolveFirstHead?.(head);
      resolveFirstHead = undefined;
      rejectFirstHead = undefined;
    };
  }

  return {
    async readLatestHead() {
      start();
      if (terminalError) throw terminalError;
      await firstHeadPromise;
      if (terminalError) throw terminalError;
      if (now() - receivedAt > maxMessageAgeMs) {
        fail(new Error("sequencer feed has not delivered a recent head"));
        throw terminalError;
      }
      return latestHead;
    },
  };
}
