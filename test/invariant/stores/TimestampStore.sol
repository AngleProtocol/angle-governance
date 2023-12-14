// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

/// @dev Because Foundry does not commit the state changes between invariant runs, we need to
/// save the current timestamp in a contract with persistent storage.
contract TimestampStore {
    uint256 public currentTimestamp;
    uint256 public currentBlockNumber;

    constructor() {
        currentTimestamp = block.timestamp;
        currentBlockNumber = block.number;
    }

    function increaseCurrentTimestamp(uint256 timeJump) external {
        currentTimestamp += timeJump;
        currentBlockNumber += 1;
    }

    function increaseCurrentBlockNumber(uint256 blockJump) external {
        currentTimestamp += 1;
        currentBlockNumber += blockJump;
    }
}
