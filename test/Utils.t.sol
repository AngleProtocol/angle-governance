// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { Test, stdError } from "forge-std/Test.sol";
import "./Constants.t.sol";

//solhint-disable
contract Utils is Test {
    function _passProposal(
        uint256 chainId,
        AngleGovernor governor,
        address timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal {
        hoax(whale);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.roll(block.number + governor.$votingDelayBlocks() + 1);

        hoax(whale);
        governor.castVote(proposalId, 1);
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        hoax(address(timelock));
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }
}
