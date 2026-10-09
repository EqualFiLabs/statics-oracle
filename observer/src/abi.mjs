export const feedAbi = [
  { type: "function", name: "l1Reporter", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "observerSetVersion", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "statusSequence", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "lastHeartbeatStatusSequence", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "lastObservedBlockNumber", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "healthyUntil", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "availabilityReason", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "threshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "observers", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
  { type: "function", name: "isObserver", stateMutability: "view", inputs: [{ name: "observer", type: "address" }], outputs: [{ type: "bool" }] },
  {
    type: "function",
    name: "latestRoundData",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
  {
    type: "function",
    name: "submitHeartbeat",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "heartbeat",
        type: "tuple",
        components: [
          { name: "observerSetVersion", type: "uint64" },
          { name: "statusSequence", type: "uint64" },
          { name: "observedBlockNumber", type: "uint64" },
          { name: "observedBlockHash", type: "bytes32" },
          { name: "validUntil", type: "uint64" },
        ],
      },
      { name: "signatures", type: "bytes[]" },
    ],
    outputs: [],
  },
];

export const reporterAbi = [
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "inbox", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "childChainId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "l2Feed", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "l2RefundAddress", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "statusGasLimit", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "configurationGasLimit", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "gasPriceBid", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "observerSetVersion", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "statusSequence", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "healthy", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "threshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "observers", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
  { type: "function", name: "isObserver", stateMutability: "view", inputs: [{ name: "observer", type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "quoteStatusRetryable", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "quoteConfigurationRetryable", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "submitStatusReport",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "report",
        type: "tuple",
        components: [
          { name: "observerSetVersion", type: "uint64" },
          { name: "sequence", type: "uint64" },
          { name: "healthy", type: "bool" },
          { name: "observedAt", type: "uint64" },
          { name: "validUntil", type: "uint64" },
        ],
      },
      { name: "signatures", type: "bytes[]" },
    ],
    outputs: [{ type: "uint256" }],
  },
];

export const heartbeatTypes = {
  Heartbeat: [
    { name: "observerSetVersion", type: "uint64" },
    { name: "statusSequence", type: "uint64" },
    { name: "observedBlockNumber", type: "uint64" },
    { name: "observedBlockHash", type: "bytes32" },
    { name: "validUntil", type: "uint64" },
  ],
};

export const statusReportTypes = {
  StatusReport: [
    { name: "observerSetVersion", type: "uint64" },
    { name: "sequence", type: "uint64" },
    { name: "healthy", type: "bool" },
    { name: "observedAt", type: "uint64" },
    { name: "validUntil", type: "uint64" },
  ],
};

export const heartbeatDomain = (feedAddress, chainId) => ({
  name: "Robinhood Sequencer Heartbeat",
  version: "1",
  chainId,
  verifyingContract: feedAddress,
});

export const statusReportDomain = (reporterAddress, chainId) => ({
  name: "Robinhood Sequencer Reporter",
  version: "1",
  chainId,
  verifyingContract: reporterAddress,
});
