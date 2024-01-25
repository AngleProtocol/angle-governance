// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "../Utils.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";

struct Proposal {
    bytes[] calldatas;
    string description;
    address[] targets;
    uint256[] values;
}

contract Propose is Utils {
    using stdJson for string;

    function setUp() public virtual override {}

    function run() external {
        (
            bytes[] memory calldatas,
            string memory description,
            address[] memory targets,
            uint256[] memory values,
            uint256[] memory chainIds
        ) = _deserializeJson();

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), 0);
        vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        AngleGovernor governor = AngleGovernor(payable(_chainToContract(CHAIN_SOURCE, ContractType.Governor)));
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log("Proposal id: %d", proposalId);

        vm.stopBroadcast();
    }
}
