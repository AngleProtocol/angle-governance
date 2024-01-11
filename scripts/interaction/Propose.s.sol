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

    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");

        (
            bytes[] memory calldatas,
            string memory description,
            address[] memory targets,
            uint256[] memory values
        ) = _deserializeJson(chainId);

        AngleGovernor governor = AngleGovernor(payable(_chainToContract(chainId, ContractType.Governor)));
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log("Proposal id: %d", proposalId);
    }
}
