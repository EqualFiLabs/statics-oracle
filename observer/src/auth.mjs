import { timingSafeEqual } from "node:crypto";

export const MIN_AUTH_TOKEN_BYTES = 32;

export function validateAuthToken(value, name) {
  if (typeof value !== "string" || Buffer.byteLength(value, "utf8") < MIN_AUTH_TOKEN_BYTES) {
    throw new Error(`${name} must contain at least ${MIN_AUTH_TOKEN_BYTES} bytes`);
  }
  if (/[\r\n]/.test(value)) throw new Error(`${name} must not contain line breaks`);
  return value;
}

export function parseObserverAuthTokens(value, observerCount) {
  const tokens = String(value).split(",").map((token) => token.trim());
  if (tokens.length !== observerCount) {
    throw new Error("OBSERVER_AUTH_TOKENS must contain one token per OBSERVER_URLS entry");
  }
  const validated = tokens.map((token, index) =>
    validateAuthToken(token, `OBSERVER_AUTH_TOKENS[${index}]`)
  );
  if (new Set(validated).size !== validated.length) {
    throw new Error("OBSERVER_AUTH_TOKENS must contain a distinct token for each observer");
  }
  return validated;
}

export function isAuthorizedBearer(header, expectedToken) {
  if (typeof header !== "string" || !header.startsWith("Bearer ")) return false;
  const supplied = Buffer.from(header.slice("Bearer ".length), "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
