// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseActor, IERC20, IERC20Metadata, AngleGovernor, TestStorage } from "./BaseActor.t.sol";
import { console } from "forge-std/console.sol";
import { IGovernor } from "oz/governance/IGovernor.sol";
import { ProposalStore, Proposal } from "../stores/ProposalStore.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";
import { TimestampStore } from "../stores/TimestampStore.sol";

contract Proposer is BaseActor {
    AngleGovernor internal _angleGovernor;
    ProposalStore public proposalStore;
    IERC5805 public veANGLEDelegation;
    TimestampStore public timestampStore;

    constructor(
        AngleGovernor angleGovernor,
        IERC20 _agToken,
        uint256 nbrVoter,
        ProposalStore _proposalStore,
        IERC5805 _veANGLEDelegation,
        TimestampStore _timestampStore
    ) BaseActor(nbrVoter, "Proposer", _agToken) {
        _angleGovernor = angleGovernor;
        proposalStore = _proposalStore;
        veANGLEDelegation = _veANGLEDelegation;
        timestampStore = _timestampStore;
    }

    function propose(uint256 value) public useActor(1) {
        address[] memory targets = new address[](1);
        bytes[] memory datas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        string memory description = "Test Proposal";
        targets[0] = address(_angleGovernor);
        datas[0] = "";
        values[0] = value;

        uint256 proposalId = _angleGovernor.hashProposal(targets, values, datas, keccak256(bytes(description)));
        if (_angleGovernor.proposalSnapshot(proposalId) != 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    _angleGovernor.state(proposalId),
                    bytes32(0)
                )
            );
        }
        _angleGovernor.propose(targets, values, datas, description);

        // Add to the store
        proposalStore.addProposal(targets, values, datas, keccak256(bytes(description)));
    }

    function execute(uint256 proposalId) public useActor(1) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        Proposal memory proposal = proposalStore.getRandomProposal(proposalId);
        uint256 proposalHash = _angleGovernor.hashProposal(
            proposal.target,
            proposal.value,
            proposal.data,
            proposal.description
        );
        uint256 proposalSnapshot = _angleGovernor.proposalSnapshot(proposalHash);
        timestampStore.increaseCurrentTimestamp(_angleGovernor.proposalDeadline(proposalHash));
        timestampStore.increaseCurrentBlockNumber(
            _angleGovernor.$snapshotTimestampToSnapshotBlockNumber(proposalSnapshot)
        );
        vm.warp(_angleGovernor.proposalDeadline(proposalHash) + 1);
        vm.roll(_angleGovernor.$snapshotTimestampToSnapshotBlockNumber(proposalSnapshot) + 1);
        IGovernor.ProposalState currentState = _angleGovernor.state(proposalHash);
        if (currentState != IGovernor.ProposalState.Succeeded) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalHash,
                    currentState,
                    bytes32(1 << uint8(IGovernor.ProposalState.Succeeded)) |
                        bytes32(1 << uint8(IGovernor.ProposalState.Queued))
                )
            );
        }
        _angleGovernor.execute(proposal.target, proposal.value, proposal.data, proposal.description);
        if (currentState == IGovernor.ProposalState.Succeeded) {
            proposalStore.removeProposal(proposalHash);
            proposalStore.addOldProposal(proposal.target, proposal.value, proposal.data, proposal.description);
        }
    }

    function tryToExecute(uint256 proposalId) public useActor(1) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        Proposal memory proposal = proposalStore.getRandomProposal(proposalId);
        uint256 proposalHash = _angleGovernor.hashProposal(
            proposal.target,
            proposal.value,
            proposal.data,
            proposal.description
        );
        uint256 proposalSnapshot = _angleGovernor.proposalSnapshot(proposalHash);
        IGovernor.ProposalState currentState = _angleGovernor.state(proposalHash);
        if (currentState != IGovernor.ProposalState.Succeeded) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalHash,
                    currentState,
                    bytes32(1 << uint8(IGovernor.ProposalState.Succeeded)) |
                        bytes32(1 << uint8(IGovernor.ProposalState.Queued))
                )
            );
        }
        _angleGovernor.execute(proposal.target, proposal.value, proposal.data, proposal.description);
        if (currentState == IGovernor.ProposalState.Succeeded) {
            proposalStore.removeProposal(proposalHash);
            proposalStore.addOldProposal(proposal.target, proposal.value, proposal.data, proposal.description);
        }
    }

    function skipVotingDelay() public useActor(1) {
        timestampStore.increaseCurrentTimestamp(_angleGovernor.votingDelay() + 1);
        vm.warp(block.timestamp + _angleGovernor.votingDelay() + 1);
        vm.roll(block.number + 1);
        console.log("block", block.number, timestampStore.currentBlockNumber());
    }
}
