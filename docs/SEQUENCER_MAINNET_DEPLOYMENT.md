# Robinhood mainnet sequencer signal deployment

This record identifies the non-upgradeable contracts deployed from the human-merged
`main` commit `4fabe1a8518ea12a26d0f61c31339b00bbd1487a` of
`EqualFiLabs/statics-oracle` (PR #18). The source in that commit includes the
EqualFi Labs header. The [machine-readable deployment manifest](../deployments/robinhood-mainnet.json)
retains the original creation evidence and tracks the current observer configuration.
The initial 2-of-3 configuration and later 3-of-5 rotation are recorded separately
below. Do not use a later record commit as the Solidity source commit.

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
`v0.8.37+commit.f401782d`. [RobinScan](https://robin.etherscan.io/address/0xeCe3F60De85705472292a44787123a8Fc46CDa54#code)
serves the Robinhood feed source and ABI. Its Etherscan V2 verification returned
`Pass - Verified` for submission
`1uyivxytq2ntxzg6dbnsudadgap194zxvbuypkzuydyzikwsw9`; a source-code read
confirmed compiler `v0.8.37+commit.f401782d` and optimizer runs `20000`.
Robinhood Blockscout remains unverified: on 2026-10-09, its verification form
listed Solidity compiler versions through `0.8.36`, while the deployed feed
uses `0.8.37`.

## Initialization and configuration

The reporter was funded with `0.005 ETH` in Ethereum transaction
`0x0be2a6333a6f1fd36f8ea05983dc218df14dcf4ec4f5309429081284972beebd`
(block 26,152,472). The one-time `initializeL2Feed` call succeeded in
transaction
`0xd885ba69d42b52a4a0597b89ad56a07658a235b60c7be84ac4f8a795e75aad1d`
(block 26,152,474). Its configuration message applied on Robinhood Chain in
transaction
`0xf2b0f52714029ee43a4be5d005dfd7401c720a834c1c91bb70bb0340f9317d44`.
The L1 and L2 observer-set versions were both `1` after initialization.
The first healthy L1 status report succeeded in transaction
`0xd69a3d10cee8f35951b3acfa8468489f144c29423993fb7b70a370fa31cc718f`
(block 26,152,581), creating retryable ticket `361921`. A later healthy
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

The initial observer set contained Singapore
`0x644039C01A3d4c14281A3deB663177533298eD36`, India
`0x88F051E075115Cce2b6958D7DbC0d4986E8F298D`, and United Kingdom
`0xcBD918495c110d8263cC89D6D1bB6cBc5E3d3B6c`, in sorted order. It used a
two-of-three threshold and hash
`0x04d01fb3f628cf7fd0130982d87c1ba682525ffe923c6fc229ae0de25a388552`.
The L1 status retryable gas limit is `200000`, configuration limit `400000`,
and gas bid `100000000` wei. The source feed is
`wss://feed.mainnet.chain.robinhood.com`; the poll interval is 30 seconds.

## Initial runtime topology

At the initial rollout, three observers ran on separate Contabo VPSs in
Singapore, the United Kingdom, and India, with the primary coordinator in US
Central. The observers use
distinct signer keys, bearer tokens, and RPC pairs; the coordinator shares its
RPC pair with Singapore. Each Node signing API
binds to `127.0.0.1:8787` only. Nginx exposes it through mutual TLS on TCP
8443, requires the coordinator's client certificate, and allows only the
coordinator's public IP. The host firewall admits TCP 8443 only from that IP.
The initial coordinator used three loopback-only Nginx proxies on ports
18781–18783; each verified the corresponding observer's server identity before forwarding
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
hour; malformed data and conflicting hashes still stop recovery. The read-only
monitor on the coordinator checks observer and on-chain state every minute. A
manual monitor run passed with all three observers healthy, status
sequence `3`, answer `0`, and more than ten minutes left on the lease.
The smoke command opens a separate short-lived feed socket and was not run
during this live rollout.

After the runtime upgrade, the US Central monitor completed ten scheduled runs
between 06:52 and 07:02 UTC on 2026-10-09 with zero failures. The coordinator
recorded two renewals and zero round errors during that watch. The heartbeat
transaction observed at the end of that watch,
`0x67f31a641c012e1e71fe97052469a2bc30d6f896e15125b65866ec0e2f84bf2b`
succeeded in Robinhood block 83,964,478. At 07:02 UTC, all three observers
were healthy, the feed reported `isUp=true`, status and heartbeat sequence `3`,
`latestRoundData.answer=0`, and a lease through 07:15:15 UTC.

## Five-observer rotation (2026-10-21–22 UTC)

No contract was redeployed. The reporter and feed addresses, runtime code hashes,
and Solidity source commit above remain the creation provenance. The owner expanded
the original set to the following five signers, sorted by address, and raised the
strict-majority threshold from two to three:

| Observer | Region | Signer |
| --- | --- | --- |
| 5 | US Central | `0x2a58B2071b0BB97A456AAd39C0E4084780eD845F` |
| 4 | Sydney | `0x5DC89E2EF7f500a45014F1966B9f365064EE676a` |
| 1 | Singapore | `0x644039C01A3d4c14281A3deB663177533298eD36` |
| 3 | India | `0x88F051E075115Cce2b6958D7DbC0d4986E8F298D` |
| 2 | United Kingdom | `0xcBD918495c110d8263cC89D6D1bB6cBc5E3d3B6c` |

The new observer-set hash is
`0xda3ec1d8abac7667cfc53fe36d2a63516a4326db83d23a11df77da4bf2c3c328`.
The tracked manifest now represents this live configuration; its
`source.commit`, contract creation transactions, and funding/initialization
transactions remain the original deployment evidence.

| Step | Chain | Successful transaction | Block | UTC |
| --- | --- | --- | ---: | --- |
| Owner `rotateObserverSet` to version 2, sequence 38; configuration retryable `0x60267` | Ethereum | `0xda0635b944bf1e9b8dac56072d6f5fc3bd78e08e43da3919dcc97d43d1a0a94a` | 26,244,359 | 2026-10-21 23:46:59 |
| Three-signer healthy report, sequence 39; status retryable `0x6026f` | Ethereum | `0x1aca81fe722bb17cf892242027b336481bc7b9ec3a3943bd3d86fe8ea11ca010` | 26,244,382 | 2026-10-21 23:51:35 |
| Configuration applied: version 2, sequence 38, threshold 3 | Robinhood Chain | `0x476493243f11a9ff1dc16d61ce026f4902d4469cdbefc31b9069dbddc9fd48de` | 94,680,958 | 2026-10-21 23:57:22 |
| L1 healthy status applied: version 2, sequence 39 | Robinhood Chain | `0x6c39fec51383d9b846e12f9f6337b4d706e919aec12005ce15bb09c3eefde0e6` | 94,684,826 | 2026-10-22 00:03:53 |
| First 3-of-5 heartbeat | Robinhood Chain | `0x0fa198384dc48b9dafffa0570da4b021e702065c417313c4df24cf0d7b5a2b59` | 94,685,018 | 2026-10-22 00:04:11 |

The L2 configuration deliberately cleared the healthy lease. Direct RPC reads
showed `isUp=false` after configuration and `isUp=true` after the new status and
heartbeat, a 6-minute-49-second interval between those two L2 transactions.
Subsequent direct reads found the same five observers on both chains, version
`2`, threshold `3`, status sequence `39`, L1 `healthy=true`, L2
`l1Healthy=true`, and `latestRoundData.answer=0`. All five authenticated
observer paths returned `HEALTHY` with zero current consecutive failures; the
coordinator and monitor timer were active, and a read-only monitor run passed.
The primary coordinator uses five loopback mTLS proxies on ports 18781–18785.
The three RPC pairs remain shared by Singapore/coordinator, UK/US Central,
and India/Sydney, so host diversity does not provide five independent RPC
providers. Host IPs, credentials, and SSH recovery details remain in the
private `~/ORACLE-HOSTS.md`.

The GitHub release is left to the human maintainer.
