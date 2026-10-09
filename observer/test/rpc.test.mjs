import assert from "node:assert/strict";
import test from "node:test";

import { parseSequencerFeedMessage, readSequencerFeedHead } from "../src/rpc.mjs";

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
