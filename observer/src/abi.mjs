export const feedAbi = [
  { type: "function", name: "observerSetVersion", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "lastObservedBlockNumber", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "healthyUntil", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "threshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "observers", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
  { type: "function", name: "isObserver", stateMutability: "view", inputs: [{ name: "observer", type: "address" }], outputs: [{ type: "bool" }] },
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
  { type: "function", name: "observerSetVersion", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "statusSequence", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "healthy", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "threshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "observers", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
  { type: "function", name: "isObserver", stateMutability: "view", inputs: [{ name: "observer", type: "address" }], outputs: [{ type: "bool" }] },
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
