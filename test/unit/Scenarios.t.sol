// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import {IGovernor} from "oz-v5/governance/IGovernor.sol";
import {IVotes} from "oz-v5/governance/extensions/GovernorVotes.sol";
import {Strings} from "oz-v5/utils/Strings.sol";

import {console} from "forge-std/console.sol";
import {Test, stdError} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {AngleGovernor} from "contracts/AngleGovernor.sol";
import {ProposalReceiver} from "contracts/ProposalReceiver.sol";
import {ProposalSender} from "contracts/ProposalSender.sol";
import {TimelockControllerWithCounter, TimelockController} from "contracts/TimelockControllerWithCounter.sol";

import {SubCall} from "./Proposal.sol";
import {SimulationSetup} from "./SimulationSetup.t.sol";
import {ILayerZeroEndpoint} from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "../Constants.t.sol";

//solhint-disable
contract Scenarios is SimulationSetup {
    event ExecuteRemoteProposal(uint16 indexed remoteChainId, bytes payload);

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function testMainnetSimpleVote() public {
        vm.selectFork(forkIdentifier[1]);

        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 1,
            target: address(governor()),
            value: 0,
            data: abi.encodeWithSelector(governor().updateQuorumNumerator.selector, 11)
        });
        string memory description = "Updating Quorum";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor().votingDelay() + 1);
        vm.roll(block.number + governor().$votingDelayBlocks() + 1);

        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.warp(block.timestamp + governor().votingPeriod() + 1);

        governor().state(proposalId);

        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + timelock(1).getMinDelay() + 1);

        assertEq(governor().quorumNumerator(), 10);
        (targets, values, calldatas) = filterChainSubCalls(1, p);
        timelock(1).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(governor().quorumNumerator(), 11);
    }

    function testMainnetBatchVote() public {
        vm.selectFork(forkIdentifier[1]);

        SubCall[] memory p = new SubCall[](2);
        p[0] = SubCall({
            chainId: 1,
            target: address(governor()),
            value: 0,
            data: abi.encodeWithSelector(governor().updateQuorumNumerator.selector, 11)
        });
        p[1] = SubCall({
            chainId: 1,
            target: address(timelock(1)),
            value: 0,
            data: abi.encodeWithSelector(timelock(1).updateDelay.selector, 1)
        });
        string memory description = "Updating Quorum and delay";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor().votingDelay() + 1);
        vm.roll(block.number + governor().$votingDelayBlocks() + 1);

        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.warp(block.timestamp + governor().votingPeriod() + 1);

        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + timelock(1).getMinDelay() + 1);

        assertEq(governor().quorumNumerator() != 11, true);
        assertEq(timelock(1).getMinDelay() != 1, true);
        (targets, values, calldatas) = filterChainSubCalls(1, p);
        timelock(1).executeBatch(targets, values, calldatas, bytes32(0), 0);
        assertEq(governor().quorumNumerator(), 11);
        assertEq(timelock(1).getMinDelay(), 1);
    }

    function testPolygonSimpleVote() public {
        vm.selectFork(forkIdentifier[1]);

        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(timelock(137).updateDelay.selector, 1)
        });
        string memory description = "Updating delay on Polygon";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor().votingDelay() + 1);
        vm.roll(block.number + governor().$votingDelayBlocks() + 1);

        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.warp(block.timestamp + governor().votingPeriod() + 1);

        vm.recordLogs();
        governor().execute{value: 0.1 ether}(targets, values, calldatas, keccak256(bytes(description))); // TODO Optimize value

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory payload;
        for (uint256 i; i < entries.length; i++) {
            if (
                entries[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)")
                    && entries[i].topics[1] == bytes32(uint256(_getLZChainId(137)))
            ) {
                payload = abi.decode(entries[i].data, (bytes));
                break;
            }
        }

        vm.selectFork(forkIdentifier[137]);
        hoax(address(_lzEndPoint(137)));
        proposalReceiver(137).lzReceive(
            _getLZChainId(1), abi.encodePacked(proposalSender(), proposalReceiver(137)), 0, payload
        );

        // Final test
        vm.warp(block.timestamp + timelock(137).getMinDelay() + 1);
        assertEq(timelock(137).getMinDelay() != 1, true);
        (targets, values, calldatas) = filterChainSubCalls(137, p);
        timelock(137).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(timelock(137).getMinDelay(), 1);
    }
}
