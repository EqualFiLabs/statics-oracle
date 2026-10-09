# Robinhood mainnet sequencer signal deployment

This record identifies the non-upgradeable contracts deployed from the human-merged
`main` commit `4fabe1a8518ea12a26d0f61c31339b00bbd1487a` of
`EqualFiLabs/statics-oracle` (PR #18). The source in that commit includes the
EqualFi Labs header. The machine-readable deployment manifest is
[`deployments/robinhood-mainnet.json`](../deployments/robinhood-mainnet.json).
Do not use the later deployment-record commit as the Solidity source commit.

## Contracts and creation evidence

| Chain | Contract | Address | Creation transaction | Block | Runtime code hash |
| --- | --- | --- | --- | ---: | --- |
| Ethereum (1) | `RobinhoodSequencerReporterL1` | `0x30AdFaEf118AcAa415d73a20D55Dc7a8CD3381B4` | `0x7dbc4bbc91ac6bc64d6638da907beb7f05ddd658f03a0c7f01ceef1a0d9dcad8` | 26,152,462 | `0x371b67f81457f3967cd1fc39009e7462b8b9b0aa117955940c6180740ddd2ea8` |
| Robinhood Chain (4663) | `RobinhoodSequencerAvailabilityFeed` | `0xeCe3F60De85705472292a44787123a8Fc46CDa54` | `0xcdc735fd642fef6aead6485a194d1654b1e5a5d0f772add66323e933f772d201` | 83,876,904 | `0x7768b4390fd3a9d6d83c9e8aaa20d4063bf1438f48b296623ab20258dd5fe653` |

Both creation receipts succeeded. The observed runtime bytecode hashes match the
local artifacts, and both creation inputs exactly match the artifact bytecode plus
constructor arguments. The deployment used Solidity `0.8.37+commit.f401782d`,
optimizer runs `20000`, and the Cancun EVM target. The reporter creation used
3,152,432 gas; the feed creation used 2,480,212 gas.

Sourcify returned exact matches for the
[reporter](https://sourcify.dev/server/verify-ui/jobs/8dcd3adc-75e2-43e1-8695-197610862f64)
and [feed](https://sourcify.dev/server/verify-ui/jobs/bcfc977f-ea18-48ca-90f1-4ceb2f8fc5ad).
[Etherscan](https://etherscan.io/address/0x30AdFaEf118AcAa415d73a20D55Dc7a8CD3381B4#code)
also serves the Ethereum reporter source, with compiler
`v0.8.37+commit.f401782d`. Robinhood Blockscout verification remains pending.
Its per-instance API returned a Cloudflare HTTP 403. The authenticated PRO
API returned HTTP 500 for multipart uploads of the Sourcify files and standard
JSON input. A form-encoded standard JSON submission was accepted, but the
asynchronous verification reported `Fail - Unable to verify`, including when
the known constructor argument was supplied explicitly. This record does not
claim Blockscout verification.

## Initialization and configuration

The reporter was funded with `0.005 ETH` in Ethereum transaction
`0x0be2a6333a6f1fd36f8ea05983dc218df14dcf4ec4f5309429081284972beebd`
(block 26,152,472). The one-time `initializeL2Feed` call succeeded in
transaction
`0xd885ba69d42b52a4a0597b89ad56a07658a235b60c7be84ac4f8a795e75aad1d`
(block 26,152,474). Its configuration message applied on Robinhood Chain in
transaction
`0xf2b0f52714029ee43a4be5d005dfd7401c720a834c1c91bb70bb0340f9317d44`.
The L1 and L2 observer-set versions are both `1`. The first healthy L1
status report succeeded in transaction
`0xd69a3d10cee8f35951b3acfa8468489f144c29423993fb7b70a370fa31cc718f`
(block 26,152,581), creating retryable ticket `361921`. The latest healthy
status, sequence `3`, was submitted in Ethereum transaction
`0x205cbec49f1a0dadf6011bdca725f35feeb5f35dfe14246948842430db1a548a`
(block 26,153,023), creating retryable ticket `362027`. It applied on
Robinhood Chain in transaction
`0x90c2ac28e569d8c398eb964f4601f0bde8ef637bc2db7aa5ca7d5929a64a0bc6`
(block 83,949,310). The first healthy heartbeat succeeded in transaction
`0x319764f4a5f95313ae0ab071fade0fe0244f8ed8db6b912ccd5428d8217d94af`
(block 83,949,456), sent by relayer
`0xCD6dF844bA4579cC04B5c65dbE602cf5566060A4`.

The temporary Ethereum owner and retryable refund address are both Statics
Treasury `0x4CF8e4D37F561815F208565a5b6Ca8a85b143205`. The intended Safe
`0x603A8A2f22ac1d61E9c932A4F6Fa23170CEcb9Ff` is not yet deployed on
Ethereum; ownership can be transferred after it is deployed there. The delayed
inbox is `0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D`.

The observer set is the sorted address list in the manifest, with a two-of-three
threshold and hash
`0x04d01fb3f628cf7fd0130982d87c1ba682525ffe923c6fc229ae0de25a388552`.
The L1 status retryable gas limit is `200000`, configuration limit `400000`,
and gas bid `100000000` wei. The source feed is
`wss://feed.mainnet.chain.robinhood.com`; the poll interval is 30 seconds.

## Runtime topology

Three observers run on separate Contabo VPSs in Singapore, the United Kingdom,
and India, with the primary coordinator in US Central. The observers use
distinct signer keys, bearer tokens, and RPC pairs; the coordinator shares its
RPC pair with Singapore. Each Node signing API
binds to `127.0.0.1:8787` only. Nginx exposes it through mutual TLS on TCP
8443, requires the coordinator's client certificate, and allows only the
coordinator's public IP. The host firewall admits TCP 8443 only from that IP.
The coordinator has three loopback-only Nginx proxies on ports 18781–18783;
each verifies the corresponding observer's server identity before forwarding
requests. Private keys and tokens are held in root-only files on their assigned
hosts. The offline CA key is retained in the local protected credentials
folder. The installed certificates expire in one year and require rotation
before expiry. VPS addresses and SSH recovery details are in the private
`~/ORACLE-HOSTS.md`, not this public record.

The exact Nginx configuration is reproducible from the
[transport templates](../observer/ops/nginx/README.md), which contain no host IPs
or secret material. SSH is key-only; password and root login are disabled.

The primary coordinator uses the funded relayer account and is supervised by
systemd. The earlier unused WireGuard package and generated keys were removed
from all four VPSs. A backup coordinator is not deployed. The original Europe,
US West, Japan, and US East Oracle service units remain disabled and inactive.

## Operational proof and release handoff

The three observers stayed healthy through a 10-minute watch before the
coordinator was started. The L1 status ticket above took about 13 minutes to
apply on Robinhood Chain. Its first heartbeat receipt succeeded; the feed then
reported sequence `3`, `isUp=true`, `latestRoundData.answer=0`, and an active
15-minute lease. A subsequent heartbeat succeeded in transaction
`0xec0188fb5250599fffa67b32f4298a6a3e7a1e1c432c9b27fc0750462eef2ea7`.

Singapore had one feed socket failure during the observer watch, and India
had two after the first heartbeat. The two-of-three quorum continued renewing.
Runtime commit `33e6752a36676cf38b7f40b43ee3c61f47e101af` adds a
five-minute reconnect cooldown and a limit of three connections per rolling
hour; malformed data and conflicting hashes still stop recovery. The current
read-only monitor on the coordinator checks observer and on-chain state every
minute. A manual monitor run passed with all three observers healthy, status
sequence `3`, answer `0`, and more than ten minutes left on the lease.
The smoke command opens a separate short-lived feed socket and was not run
during this live rollout.

After the runtime upgrade, the US Central monitor completed ten scheduled runs
between 06:52 and 07:02 UTC on 2026-10-09 with zero failures. The coordinator
recorded two renewals and zero round errors during that watch. The latest
heartbeat transaction
`0x67f31a641c012e1e71fe97052469a2bc30d6f896e15125b65866ec0e2f84bf2b`
succeeded in Robinhood block 83,964,478. At 07:02 UTC, all three observers
were healthy, the feed reported `isUp=true`, status and heartbeat sequence `3`,
`latestRoundData.answer=0`, and a lease through 07:15:15 UTC.

The GitHub release is left to the human maintainer.
