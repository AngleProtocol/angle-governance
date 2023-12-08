// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./BaseActor.t.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";
import { MockANGLE } from "../../external/MockANGLE.sol";
import "contracts/interfaces/IveANGLE.sol";
import "contracts/utils/Errors.sol";
import { console } from "forge-std/console.sol";
import { TimestampStore } from "../stores/TimestampStore.sol";

contract Param is BaseActor {
    IveANGLE public veToken;
    TimestampStore public timestampStore;

    constructor(
        uint256 _nbrActor,
        IERC20 _agToken,
        TimestampStore _timestampStore
    ) BaseActor(_nbrActor, "Param", _agToken) {
        timestampStore = _timestampStore;
    }

    function wrap(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, 365 days * 5);
        timestampStore.increaseCurrentTimestamp(timestamp);
        vm.warp(timestampStore.currentTimestamp());
    }
}
