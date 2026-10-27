// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { ExecutionVerifierMock } from "test/mocks/ExecutionOracleMocks.sol";

contract ExecutionRegistryHandler is Test {
    StaticsExecutionOracle public oracle;
    uint64 public successfulMutations;
    bool public enabledUpdateAccepted;
    mapping(bytes32 => bytes32) public enabledHash;

    constructor() {
        oracle = new StaticsExecutionOracle(address(this), address(new ExecutionVerifierMock()), 5);
    }

    function market(
        uint8 seed
    ) public pure returns (bytes32) {
        return bytes32(uint256(seed % 4) + 1);
    }

    function config(
        uint256 seed
    ) internal pure returns (IEO.ExecutionMarketConfigInput memory) {
        return IEO.ExecutionMarketConfigInput(
            bytes32((uint256(3) << 240) | 1234),
            uint32(bound(seed, 1, type(uint32).max)),
            uint32(bound(seed, 1, type(uint32).max)),
            uint8(seed % 19)
        );
    }

    function register(
        uint8 key,
        uint256 seed
    ) external {
        bytes32 id = market(key);
        if (oracle.marketConfig(id).status != IEO.MarketStatus.UNSET) return;
        oracle.registerMarket(id, config(seed));
        ++successfulMutations;
    }

    function enable(
        uint8 key
    ) external {
        bytes32 id = market(key);
        if (oracle.marketConfig(id).status != IEO.MarketStatus.CANDIDATE) return;
        oracle.enableMarket(id);
        enabledHash[id] = oracle.configHash(id);
        ++successfulMutations;
    }

    function disable(
        uint8 key
    ) external {
        bytes32 id = market(key);
        IEO.MarketStatus status = oracle.marketConfig(id).status;
        if (status != IEO.MarketStatus.CANDIDATE && status != IEO.MarketStatus.ENABLED) return;
        oracle.disableMarket(id);
        ++successfulMutations;
    }

    function update(
        uint8 key,
        uint256 seed
    ) external {
        bytes32 id = market(key);
        if (oracle.marketConfig(id).status != IEO.MarketStatus.DISABLED) return;
        oracle.updateMarket(id, config(seed));
        ++successfulMutations;
    }

    function attemptEnabledUpdate(
        uint8 key,
        uint256 seed
    ) external {
        bytes32 id = market(key);
        if (oracle.marketConfig(id).status != IEO.MarketStatus.ENABLED) return;
        try oracle.updateMarket(id, config(seed)) {
            enabledUpdateAccepted = true;
        } catch { }
    }
}

contract ExecutionRegistryInvariantTest is Test {
    ExecutionRegistryHandler internal handler;

    function setUp() public {
        handler = new ExecutionRegistryHandler();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.register.selector;
        selectors[1] = handler.enable.selector;
        selectors[2] = handler.disable.selector;
        selectors[3] = handler.update.selector;
        selectors[4] = handler.attemptEnabledUpdate.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariantEnabledBindingsCannotChangeAndVersionsTrackSuccessfulMutations() public view {
        assertFalse(handler.enabledUpdateAccepted());
        StaticsExecutionOracle oracle = handler.oracle();
        assertEq(oracle.registryVersion(), handler.successfulMutations());
        for (uint8 i; i < 4; ++i) {
            bytes32 id = handler.market(i);
            if (oracle.marketConfig(id).status == IEO.MarketStatus.ENABLED) {
                assertEq(oracle.configHash(id), handler.enabledHash(id));
            }
        }
    }
}
