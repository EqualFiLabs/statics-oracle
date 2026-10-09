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

test("stale feeds close once and respect the reconnect cooldown", async () => {
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
  await assert.rejects(reader.readLatestHead(), /recent head/);
  assert.equal(sockets.length, 1);
  assert.equal(sockets[0].closeCount, 1);
});

test("failed connections do not retry before the cooldown", async () => {
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

test("failed feed sockets reconnect at most three times per hour", async () => {
  const sockets = [];
  let currentTime = 1_000;
  class FakeWebSocket {
    constructor() { sockets.push(this); this.closeCount = 0; }
    close() { this.closeCount += 1; }
    push(data) { this.onmessage?.({ data }); }
    fail() { this.onerror?.(); }
  }
  const reader = createSequencerFeedReader("wss://feed.example.test", {
    WebSocketClass: FakeWebSocket,
    now: () => currentTime,
  });
  const first = reader.readLatestHead();
  sockets[0].push(feedMessage(41));
  await first;
  sockets[0].fail();
  await assert.rejects(reader.readLatestHead(), /connection failed/);
  currentTime += 300_000;
  const second = reader.readLatestHead();
  assert.equal(sockets.length, 2);
  sockets[1].push(feedMessage(42));
  assert.equal((await second).number, 42n);
  sockets[1].fail();
  currentTime += 300_000;
  const third = reader.readLatestHead();
  assert.equal(sockets.length, 3);
  sockets[2].push(feedMessage(43));
  assert.equal((await third).number, 43n);
  sockets[2].fail();
  currentTime += 300_000;
  await assert.rejects(reader.readLatestHead(), /connection failed/);
  assert.equal(sockets.length, 3);
  currentTime = 3_601_001;
  const fourth = reader.readLatestHead();
  assert.equal(sockets.length, 4);
  sockets[3].push(feedMessage(44));
  assert.equal((await fourth).number, 44n);
});

test("invalid feed data never triggers a reconnect", async () => {
  const sockets = [];
  let currentTime = 1_000;
  class FakeWebSocket {
    constructor() { sockets.push(this); }
    close() {}
    push(data) { this.onmessage?.({ data }); }
  }
  const reader = createSequencerFeedReader("wss://feed.example.test", {
    WebSocketClass: FakeWebSocket,
    now: () => currentTime,
  });
  const first = reader.readLatestHead();
  sockets[0].push(feedMessage(41));
  await first;
  sockets[0].push("{invalid");
  currentTime += 3_600_001;
  await assert.rejects(reader.readLatestHead(), /invalid sequencer feed message/);
  assert.equal(sockets.length, 1);
});
