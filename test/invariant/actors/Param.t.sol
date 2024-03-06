// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./BaseActor.t.sol";
import {IERC5805} from "oz-v5/interfaces/IERC5805.sol";
import {MockANGLE} from "../../external/MockANGLE.sol";
import "contracts/interfaces/IveANGLE.sol";
import "contracts/utils/Errors.sol";
import {console} from "forge-std/console.sol";

contract Param is BaseActor {
    IveANGLE public veToken;

    constructor(uint256 _nbrActor, IERC20 _agToken) BaseActor(_nbrActor, "Param", _agToken) {}

    function wrap(uint256 duration) public {
        duration = bound(duration, 0, 365 days);
        vm.warp(block.timestamp + duration);
        vm.roll(block.number + 1);
    }
}
