// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract MyScript is Script {
    function test() external {
        vm.startBroadcast();

        address _sender = address(uint160(uint256(keccak256(abi.encodePacked("sender")))));
        address _receiver = address(uint160(uint256(keccak256(abi.encodePacked("receiver")))));

        vm.stopBroadcast();
    }
}
