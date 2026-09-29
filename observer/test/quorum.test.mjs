import assert from "node:assert/strict";
import test from "node:test";

import { recoverAuthorizedSignatures } from "../src/quorum.mjs";

const observerA = "0x0000000000000000000000000000000000000010";
const observerB = "0x0000000000000000000000000000000000000020";
const outsider = "0x0000000000000000000000000000000000000030";

test("malformed, duplicate, and unauthorized responses cannot suppress an honest quorum", async () => {
  const recoveredBySignature = new Map([
    ["sig-a", observerA],
    ["sig-a-duplicate", observerA],
    ["sig-b", observerB],
    ["sig-outsider", outsider],
  ]);
  const settled = [
    { status: "fulfilled", value: { signature: "malformed" } },
    { status: "fulfilled", value: { signature: "sig-b" } },
    { status: "rejected", reason: new Error("offline") },
    { status: "fulfilled", value: { signature: "sig-a" } },
    { status: "fulfilled", value: { signature: "sig-a-duplicate" } },
    { status: "fulfilled", value: { signature: "sig-outsider" } },
  ];

  const quorum = await recoverAuthorizedSignatures({
    settled,
    authorizedObservers: [observerA, observerB],
    recover: async (signature) => {
      const observer = recoveredBySignature.get(signature);
      if (!observer) throw new Error("bad signature");
      return observer;
    },
  });

  assert.deepEqual(quorum, [
    { observer: observerA, signature: "sig-a-duplicate" },
    { observer: observerB, signature: "sig-b" },
  ]);
});
