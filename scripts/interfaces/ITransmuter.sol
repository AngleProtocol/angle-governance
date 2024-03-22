// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "transmuter/transmuter/Storage.sol" as Storage;

interface OldTransmuter {
    function getOracle(
        address
    ) external view returns (Storage.OracleReadType, Storage.OracleReadType, bytes memory, bytes memory);
}
