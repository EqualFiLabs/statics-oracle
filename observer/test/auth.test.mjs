import assert from "node:assert/strict";
import test from "node:test";

import {
  isAuthorizedBearer,
  parseObserverAuthTokens,
  validateAuthToken,
} from "../src/auth.mjs";

const tokenA = "a".repeat(32);
const tokenB = "b".repeat(32);

test("requires strong observer API tokens without disclosing them", () => {
  assert.equal(validateAuthToken(tokenA, "TOKEN"), tokenA);
  assert.throws(() => validateAuthToken("short", "TOKEN"), /at least 32 bytes/);
  assert.throws(() => validateAuthToken(`${tokenA}\n`, "TOKEN"), /line breaks/);
});

test("maps exactly one secret slot to each observer URL", () => {
  assert.deepEqual(parseObserverAuthTokens(`${tokenA},${tokenB}`, 2), [tokenA, tokenB]);
  assert.throws(
    () => parseObserverAuthTokens(tokenA, 2),
    /one token per OBSERVER_URLS entry/,
  );
  assert.throws(
    () => parseObserverAuthTokens(`${tokenA},${tokenA}`, 2),
    /distinct token for each observer/,
  );
});

test("accepts only the exact bearer token", () => {
  assert.equal(isAuthorizedBearer(`Bearer ${tokenA}`, tokenA), true);
  assert.equal(isAuthorizedBearer(`Bearer ${tokenB}`, tokenA), false);
  assert.equal(isAuthorizedBearer(tokenA, tokenA), false);
  assert.equal(isAuthorizedBearer(undefined, tokenA), false);
});
