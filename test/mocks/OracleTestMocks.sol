// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract OracleTokenTestMock {
    uint8 internal _decimals;
    bool public decimalsCallFails;
    bool public pauseCallFails;
    bool public oraclePausedValue;
    uint256 public uiMultiplier = 1e18;

    constructor(
        uint8 decimals_
    ) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        if (decimalsCallFails) revert("decimals failed");
        return _decimals;
    }

    function oraclePaused() external view returns (bool) {
        if (pauseCallFails) revert("pause failed");
        return oraclePausedValue;
    }

    function setDecimalsCallFails(
        bool value
    ) external {
        decimalsCallFails = value;
    }

    function setPauseCallFails(
        bool value
    ) external {
        pauseCallFails = value;
    }

    function setOraclePaused(
        bool value
    ) external {
        oraclePausedValue = value;
    }

    function setUiMultiplier(
        uint256 value
    ) external {
        uiMultiplier = value;
    }
}

contract OracleFeedTestMock {
    uint8 internal _decimals;
    string internal _description;
    bool public decimalsCallFails;
    bool public descriptionCallFails;
    bool public latestRoundCallFails;
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(
        uint8 decimals_,
        string memory description_
    ) {
        _decimals = decimals_;
        _description = description_;
    }

    function decimals() external view returns (uint8) {
        if (decimalsCallFails) revert("decimals failed");
        return _decimals;
    }

    function description() external view returns (string memory) {
        if (descriptionCallFails) revert("description failed");
        return _description;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (latestRoundCallFails) revert("round failed");
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function setDecimalsCallFails(
        bool value
    ) external {
        decimalsCallFails = value;
    }

    function setDescriptionCallFails(
        bool value
    ) external {
        descriptionCallFails = value;
    }

    function setLatestRoundCallFails(
        bool value
    ) external {
        latestRoundCallFails = value;
    }

    function setRound(
        int256 answer_,
        uint256 updatedAt_
    ) external {
        setRoundData(1, answer_, updatedAt_, updatedAt_, 1);
    }

    function setRoundData(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) public {
        roundId = roundId_;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }
}
