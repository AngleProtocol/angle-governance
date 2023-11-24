// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { stdStorage, StdStorage, Test, stdError } from "forge-std/Test.sol";
import "./Constants.t.sol";

//solhint-disable
contract Utils is Test {
    using stdStorage for StdStorage;

    function _passProposal(
        AngleGovernor governor,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        hoax(whale);
        proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.roll(block.number + governor.$votingDelayBlocks() + 1);

        hoax(whale);
        governor.castVote(proposalId, 1);
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        stdstore.target(address(governor)).sig("timelock()").checked_write(address(governor));
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function mineBlocksBySecond(uint256 secondsElapsed) public {
        uint256 timeElapsed = secondsElapsed;
        uint256 blocksElapsed = secondsElapsed / 12;
        vm.warp(block.timestamp + timeElapsed);
        vm.roll(block.number + blocksElapsed);
    }
}
