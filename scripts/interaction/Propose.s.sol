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

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/proposals.json");
        string memory json = vm.readFile(path);
        bytes memory proposalDetails = json.parseRaw(string.concat(".", vm.toString(chainId)));
        Proposal memory rawProposal = abi.decode(proposalDetails, (Proposal));

        AngleGovernor governor = AngleGovernor(payable(_chainToContract(chainId, ContractType.Governor)));
        uint256 proposalId = governor.propose(
            rawProposal.targets,
            rawProposal.values,
            rawProposal.calldatas,
            rawProposal.description
        );
        console.log("Proposal id: %d", proposalId);
    }
}
