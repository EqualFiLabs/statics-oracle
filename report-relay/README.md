# BucketPerps signed report relay

Node 22 or later; CI uses Node 24. Install with npm ci and run npm start after
loading a private server environment. The official Chainlink SDK is pinned.
Set the Data Streams API key/secret and a separate random access token of at least
32 characters. Credentials never enter clients, responses, logs or manifests.
SDK error objects and authentication headers are not logged.

Production mode requires a fully qualified manifest. Qualification mode permits
candidate streams with explicit provisional bundle size, delay and window values;
these values do not establish production readiness. The default manifests remain
candidates until real signed authentication and timing qualification are complete.

The listener binds loopback only. A separately configured application gateway may
access the narrow endpoint with its server-side bearer token. Never embed that
token in a public frontend or expose the listener without appropriate access
control under the reviewed subscription terms. The endpoint is not a generic
feed-ID/history API. Independent frontends can obtain approved signed reports
elsewhere and submit them through the consumer without this service.

POST /v1/bucketperps/execution-reports accepts only {"marketId":"BTC_USD"}.
A successful response contains the configured label/stream, exact signed bytes
and servedAt. Only reports[] is passed to the consumer. The oracle independently
authenticates every report and chooses the price. Relay metadata is untrusted.
Insufficient, stale, ambiguous or nonadjacent coverage returns availability failure.

GET /v1/bucketperps/health uses the same bearer protection and reports readiness,
observation lag, gaps, buffer eviction, recovery failures and reconnect counters.
These local-clock metrics aid operations; they are not production timing evidence.
Buffers are bounded, deduplicated and chronological. Recovery uses bounded pages
at startup, after reconnect and periodically. Expired/future/wrong-stream bodies
are rejected, and signed bytes are never rewritten. Shutdown closes stream and
listener; upstream requests have bounded SDK timeouts. No price fallback exists.
