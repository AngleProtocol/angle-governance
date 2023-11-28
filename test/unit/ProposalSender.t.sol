// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";

import { console } from "forge-std/console.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender, Ownable } from "contracts/ProposalSender.sol";

import { SubCall } from "./Proposal.sol";
import { SimulationSetup } from "./SimulationSetup.t.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "../Constants.t.sol";

//solhint-disable
contract ProposalSenderTest is SimulationSetup {
    event ExecuteRemoteProposal(uint16 indexed remoteChainId, bytes payload);

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function test_MainnetChangeAngleGovernorAndTimelock() public {
        vm.selectFork(forkIdentifier[1]);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute
        TimelockController timelock2 = new TimelockController(1 days, proposers, executors, address(this));
        AngleGovernor governor2 = new AngleGovernor(
            veANGLEDelegation,
            address(timelock2),
            initialVotingDelay,
            initialVotingPeriod,
            initialProposalThreshold,
            initialVoteExtension,
            initialQuorumNumerator,
            initialShortCircuitNumerator,
            initialVotingDelayBlocks
        );
        timelock2.grantRole(timelock2.PROPOSER_ROLE(), address(governor2));
        timelock2.grantRole(timelock2.CANCELLER_ROLE(), multisig(chainIds[1]));

        vm.label(address(timelock2), "New timelock");
        vm.label(address(governor2), "New governor");

        // In a real setup you would need to set also the owner of all angle contracts to the new timelock

        // either the long road
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 1,
            target: address(governor()),
            value: 0,
            // not direct way to call this function, but just to use the utils functions
            data: abi.encodeWithSelector(
                governor().relay.selector,
                proposalSender(),
                0,
                abi.encodeWithSelector(proposalSender().transferOwnership.selector, address(governor2))
            )
        });
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        // or the short one with no timelock
        targets[0] = address(proposalSender());
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(proposalSender().transferOwnership.selector, address(governor2));

        string memory description = "Updating Angle Governor";
        _shortcutProposal(1, description, targets, values, calldatas);
        assertEq(_proposalSender.owner(), address(governor()));
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(_proposalSender.owner(), address(governor2));

        // reset back to the old governor
        calldatas[0] = abi.encodeWithSelector(proposalSender().transferOwnership.selector, address(governor()));
        // Then let's try to pass a proposal with the old timelock/governor
        _shortcutProposal(1, description, targets, values, calldatas);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, governor()));
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));

        // Set in current contract storage the governor and timelock
        AngleGovernor realGovernor = governor();
        TimelockController realTimelock = timelock(1);
        _governor = governor2;
        _timelocks[1] = timelock2;

        // Pass a proposal with the new timelock/governor
        _shortcutProposal(1, description, targets, values, calldatas);
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));

        // reset the storage for other test
        _governor = realGovernor;
        _timelocks[1] = realTimelock;

        assertEq(_proposalSender.owner(), address(governor()));
        assertEq(_proposalSender.owner(), address(realGovernor));
    }

    function test_PolygonUpdateProposalReceiver() public {
        vm.selectFork(forkIdentifier[137]);
        ProposalReceiver proposalReceiver2 = new ProposalReceiver(address(lzEndPoint(137)));
        proposalReceiver2.setTrustedRemoteAddress(getLZChainId(1), abi.encodePacked(_proposalSender));
        proposalReceiver2.transferOwnership(address(timelock(137)));
        address newProposalReceiver = address(proposalReceiver2);

        vm.selectFork(forkIdentifier[1]);

        SubCall[] memory p = new SubCall[](3);
        p[0] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(1).grantRole.selector,
                timelock(1).PROPOSER_ROLE(),
                newProposalReceiver
            )
        });
        p[1] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(1).revokeRole.selector,
                timelock(1).PROPOSER_ROLE(),
                address(proposalReceiver(137))
            )
        });
        p[2] = SubCall({
            chainId: 1,
            target: address(proposalSender()),
            value: 0,
            data: abi.encodeWithSelector(
                proposalSender().setTrustedRemoteAddress.selector,
                getLZChainId(137),
                abi.encodePacked(proposalReceiver2)
            )
        });

        string memory description = "Updating Proposal receiver on Polygon";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor().votingDelay() + 1);
        vm.roll(block.number + governor().$votingDelayBlocks() + 1);

        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.warp(block.timestamp + governor().votingPeriod() + 1);

        vm.recordLogs();
        governor().execute{ value: 0.1 ether }(targets, values, calldatas, keccak256(bytes(description))); // TODO Optimize value

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory payload;
        for (uint256 i; i < entries.length; i++) {
            if (
                entries[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)") &&
                entries[i].topics[1] == bytes32(uint256(getLZChainId(137)))
            ) {
                payload = abi.decode(entries[i].data, (bytes));
                break;
            }
        }

        vm.selectFork(forkIdentifier[137]);
        hoax(address(lzEndPoint(137)));
        proposalReceiver(137).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(137)),
            0,
            payload
        );

        // Final test
        vm.warp(block.timestamp + timelock(137).getMinDelay() + 1);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver(137))), true);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver2)), false);
        (targets, values, calldatas) = filterChainSubCalls(137, p);
        timelock(137).executeBatch(targets, values, calldatas, bytes32(0), 0);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver(137))), false);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver2)), true);
    }
}
