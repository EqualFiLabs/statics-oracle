export async function recoverAuthorizedSignatures({ settled, authorizedObservers, recover }) {
  const authorized = new Set(authorizedObservers.map((value) => value.toLowerCase()));
  const signatures = [];
  for (const result of settled) {
    if (result.status !== "fulfilled") continue;
    try {
      const recovered = await recover(result.value.signature);
      if (!authorized.has(recovered.toLowerCase())) continue;
      signatures.push({ observer: recovered, signature: result.value.signature });
    } catch {
      continue;
    }
  }

  const unique = new Map(signatures.map((value) => [value.observer.toLowerCase(), value]));
  return [...unique.values()].sort((a, b) =>
    BigInt(a.observer) < BigInt(b.observer) ? -1 : 1,
  );
}
