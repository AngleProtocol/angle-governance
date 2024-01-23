// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract Simulate is Script {
    error WrongCall();

    function run() external {
        // TODO replace with your inputs
        address sender = address(0xcC617C6f9725eACC993ac626C7efC6B96476916E);
        address contractAddress = address(0x748bA9Cd5a5DDba5ABA70a4aC861b2413dCa4436);
        // remove the 0x
        bytes memory data = hex"000";

        vm.prank(sender, sender);
        (bool success, ) = contractAddress.call{ value: 0.6 ether }(data);
        if (!success) revert WrongCall();
    }
}
