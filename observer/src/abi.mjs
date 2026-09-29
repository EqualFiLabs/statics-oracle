export const feedAbi = [
  {
    type: "function",
    name: "observerSetVersion",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint64" }],
  },
  {
    type: "function",
    name: "lastObservedBlockNumber",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint64" }],
  },
  {
    type: "function",
    name: "threshold",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "observers",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    type: "function",
    name: "isObserver",
    stateMutability: "view",
    inputs: [{ name: "observer", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "submitObservation",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "observation",
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

export const observationTypes = {
  Observation: [
    { name: "observerSetVersion", type: "uint64" },
    { name: "observedBlockNumber", type: "uint64" },
    { name: "observedBlockHash", type: "bytes32" },
    { name: "validUntil", type: "uint64" },
  ],
};

export const eip712Domain = (feedAddress) => ({
  name: "Robinhood Sequencer Signal",
  version: "1",
  chainId: 4663,
  verifyingContract: feedAddress,
});
