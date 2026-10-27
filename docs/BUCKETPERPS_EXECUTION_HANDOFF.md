# BucketPerps task 18 handoff

The execution adapter and signed-report relay are ready for application integration
work. The actual BucketPerps Diamond, accounting and liquidation paths are not
implemented in this repository. Task 18 remains open until those contracts exist.

## Consumer contract

Use `IStaticsExecutionOracle` as the integration ABI. Store one oracle address in
the ratified BucketPerps namespace. Controlled configuration must reject zero and
no-code addresses and emit its change event. Before enabling price-sensitive
operations, configure the existing sequencer binding and authorize the Diamond
address in the oracle. Facets that execute by delegatecall call the oracle as the
Diamond; authorizing individual facet addresses does not authorize the Diamond.

Every long/short open, close and liquidation entry point accepts `bytes[]` reports
and calls the same nonpayable, non-view primitive in the economic transaction:

```solidity
IStaticsExecutionOracle.ExecutionPrice memory execution =
    oracle.verifyExecutionPrice(marketId, reports);
uint256 price1e18 = execution.price1e18;
```

Use only this returned price for accounting, settlement and liquidation. The
returned stream ID and signed interval identify the authenticated report. Emit
market ID, price and observation timestamp in the corresponding economic event.
A caller-supplied price, relay metadata, local clock or previously verified price
must not determine the economic result. The oracle stores no execution watermark
or latest price; repeated independent actions may use the same valid signed report.

The oracle derives `referenceTimestamp = block.timestamp - executionDelay` for the
configured market, authenticates every submitted report, validates every body and
requires exactly one inclusive signed interval to contain the reference. Input
order has no authority. Matching duplicates revert; nonmatching duplicates count
toward the immutable bundle bound. Decimal conversion uses the configured stream
precision and returns 18 decimals. Native verification fees are unsupported; the
reviewed subscription verifier receives no native value and empty fee parameters.
Qualify the actual subscription entitlement and verifier behavior before release.

## Integration acceptance checklist

| Subtask | Required BucketPerps behavior |
| --- | --- |
| 18.1 | One oracle address in ratified namespaced Diamond storage |
| 18.2 | Controlled migration, zero/code checks, configuration event |
| 18.3 | Both opening directions use the returned oracle price exactly |
| 18.4 | Both closing directions settle with the same primitive |
| 18.5 | Liquidators submit reports; the oracle determines liquidation price |
| 18.6 | Economic events include market, execution price and observation evidence |
| 18.7 | Every oracle failure reverts all action effects |

Do not catch an oracle failure and continue the economic action. Apply the
Diamond's reentrancy protection around external interactions. Assert rollback of
positions, margin, house/FIFO state, fees and staking/rewards for authentication
failure, missing coverage, overlapping matches, invalid bodies, sequencer outage,
recovery grace, expired sequencer lease and removed consumer authorization.
The existing test consumer proves call-level rollback only; it does not prove
BucketPerps accounting rollback. Task 19 must exercise the actual Diamond paths.

## Application boundary

The protected relay endpoint accepts a configured market label and returns exact
opaque report bytes. Pass only its `reports` array to the economic consumer. Keep
subscription credentials and the relay bearer token on the server; an application
gateway supplies browser-facing delivery. Independently obtained reports from the
approved stream work through the same consumer without a relay signature.
Unavailable coverage returns an availability error. Refresh reports and retry the
whole action; inclusion time can change the matching interval. Never retry with a
substituted price or a weaker oracle route.

Candidate market labels and IDs are in the network-specific reviewed manifests.
Their timing and bundle values remain unratified, and their production enablement
is blocked. Mainnet and testnet stream IDs differ. No oracle deployment, consumer
authorization or BucketPerps migration has been performed.

## Remaining qualification

The optional real-report fork test needs a licensed private capture and configured
subscription access. Current credentials were unavailable during implementation,
so signed relay output has not yet been authenticated end to end against the real
verifier. Run that check before treating checkpoint D as satisfied.

Tasks 18–26 remain open. Build and test the Diamond integration, measure report
availability and transaction inclusion, select production parameters, qualify
downstream economics, and obtain explicit deployment authorization before release.
Deterministic interval selection alone does not establish economic safety.
