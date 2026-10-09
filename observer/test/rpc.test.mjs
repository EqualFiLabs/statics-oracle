import assert from "node:assert/strict";
import test from "node:test";

import {
  createSequencerFeedReader,
  parseSequencerFeedMessage,
  readSequencerFeedHead,
} from "../src/rpc.mjs";

function feedMessage(number, hashByte = "22") {
  return JSON.stringify({
    version: 1,
    messages: [{
      sequenceNumber: number,
      blockHash: `0x${hashByte.repeat(32)}`,
      message: { message: { header: { timestamp: 1_000 } } },
    }],
  });
}

test("parses the newest usable Nitro sequencer-feed message", () => {
  const olderHash = `0x${"11".repeat(32)}`;
  const newerHash = `0x${"22".repeat(32)}`;
  const head = parseSequencerFeedMessage(JSON.stringify({
    version: 1,
    messages: [
      {
        sequenceNumber: 41,
        blockHash: olderHash,
        message: { message: { header: { timestamp: 900 } } },
      },
      { sequenceNumber: 42, blockHash: null, message: {} },
      {
        sequenceNumber: 43,
        blockHash: newerHash,
        message: { message: { header: { timestamp: 1_000 } } },
      },
    ],
  }));

  assert.deepEqual(head, { number: 43n, hash: newerHash, timestamp: 1_000n });
});

test("rejects malformed or unsupported feed messages", () => {
  assert.throws(() => parseSequencerFeedMessage("{}"), /no usable block/);
  assert.throws(
    () => parseSequencerFeedMessage(JSON.stringify({ version: 2, messages: [] })),
    /no usable block/,
  );
});

test("feed errors close once even when close fires another error", async (context) => {
  const original = globalThis.WebSocket;
  let socket;
  class ErroringWebSocket {
    constructor() {
      socket = this;
      this.closeCount = 0;
      queueMicrotask(() => this.onerror?.());
    }

    close() {
      this.closeCount += 1;
      this.onerror?.();
    }
  }
  globalThis.WebSocket = ErroringWebSocket;
  context.after(() => { globalThis.WebSocket = original; });

  await assert.rejects(readSequencerFeedHead("wss://feed.example.test"), /connection failed/);
  assert.equal(socket.closeCount, 1);
});

test("service samples reuse one open feed connection", async () => {
  const sockets = [];
  let currentTime = 1_000;
  class FakeWebSocket {
    constructor(url) {
      assert.equal(url, "wss://feed.example.test");
      this.closeCount = 0;
      sockets.push(this);
    }

    close() { this.closeCount += 1; }
    push(data) { this.onmessage?.({ data }); }
  }
  const reader = createSequencerFeedReader("wss://feed.example.test", {
    WebSocketClass: FakeWebSocket,
    now: () => currentTime,
  });
  const initial = reader.readLatestHead();
  assert.equal(sockets.length, 1);
  sockets[0].push(feedMessage(41));
  assert.equal((await initial).number, 41n);
  assert.equal((await reader.readLatestHead()).number, 41n);
  currentTime += 30_000;
  sockets[0].push(feedMessage(42));
  assert.equal((await reader.readLatestHead()).number, 42n);
  assert.equal(sockets.length, 1);
  assert.equal(sockets[0].closeCount, 0);
});

test("stale or closed feeds fail without opening another connection", async () => {
  const sockets = [];
  let currentTime = 1_000;
  class FakeWebSocket {
    constructor() { sockets.push(this); this.closeCount = 0; }
    close() { this.closeCount += 1; }
    push(data) { this.onmessage?.({ data }); }
  }
  const reader = createSequencerFeedReader("wss://feed.example.test", {
    WebSocketClass: FakeWebSocket,
    maxMessageAgeMs: 60_000,
    now: () => currentTime,
  });
  const initial = reader.readLatestHead();
  sockets[0].push(feedMessage(41));
  await initial;
  currentTime += 60_001;
  await assert.rejects(reader.readLatestHead(), /recent head/);
  sockets[0].onclose();
  await assert.rejects(reader.readLatestHead(), /connection closed/);
  assert.equal(sockets.length, 1);
  assert.equal(sockets[0].closeCount, 1);
});

test("connection failure is terminal rather than a reconnect loop", async () => {
  let connections = 0;
  class FailingWebSocket {
    constructor() {
      connections += 1;
      queueMicrotask(() => this.onerror?.());
    }

    close() {}
  }
  const reader = createSequencerFeedReader("wss://feed.example.test", {
    WebSocketClass: FailingWebSocket,
  });
  await assert.rejects(reader.readLatestHead(), /connection failed/);
  await assert.rejects(reader.readLatestHead(), /connection failed/);
  assert.equal(connections, 1);
});
