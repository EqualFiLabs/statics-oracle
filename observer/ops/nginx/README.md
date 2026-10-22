# Private observer transport

These templates describe the mainnet mutual-TLS transport. The observer Node
process must bind only to `127.0.0.1:8787`; the coordinator Node process uses
its five local ports `18781`–`18785` for the recorded 3-of-5 mainnet configuration.
Substitute the coordinator IP, five observer IPs, and five observer DNS identities
before installing the Nginx files at
`/etc/nginx/conf.d/statics-oracle.conf`. The DNS names are certificate
identities; the proxies connect to fixed IPv4 addresses.

Create one proxy per observer in the reviewed deployment manifest. Keep `OBSERVER_URLS`
and `OBSERVER_AUTH_TOKENS` in matching order and include all five mainnet observers;
the smoke check and monitor reject a different endpoint count or signer set. For the
separate 2-of-3 testnet deployment, render only its three observer proxies and use its
manifest and three matching endpoint/token pairs.

Each observer holds only its own server certificate and key plus the CA
certificate in `/etc/equalfi/statics-oracle/tls/`. The coordinator holds only
its client certificate and key plus the CA certificate there. Directory mode
is `0700`; file mode is `0600`, owned by root. Retain the CA private key
off-host. The observer servers require the coordinator client certificate,
limit requests, and restrict the source IP; UFW separately admits TCP 8443 only
from the coordinator. The coordinator verifies every observer server
certificate. The local HTTP hop stays on loopback.

Validate each rendered file with `nginx -t` before enabling Nginx. From the
coordinator, verify an authenticated `/health` request to each local proxy and
verify that a direct connection without the client certificate is rejected.
Keep SSH key-only; do not publish the Node API or local coordinator ports.
Rotate leaf certificates before their `notAfter` date and reload Nginx after
successful certificate and configuration validation.
