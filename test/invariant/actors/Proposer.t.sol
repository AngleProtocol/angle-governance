// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BaseActor, IERC20, IERC20Metadata, AngleGovernor, TestStorage} from "./BaseActor.t.sol";
import {console} from "forge-std/console.sol";
import {IGovernor} from "oz/governance/IGovernor.sol";
import {ProposalStore, Proposal} from "../stores/ProposalStore.sol";
import {IERC5805} from "oz/interfaces/IERC5805.sol";

contract Proposer is BaseActor {
    AngleGovernor internal _angleGovernor;
    ProposalStore public proposalStore;
    IERC5805 public veANGLEDelegation;

    constructor(
        AngleGovernor angleGovernor,
        IERC20 _agToken,
        uint256 nbrVoter,
        ProposalStore _proposalStore,
        IERC5805 _veANGLEDelegation
    ) BaseActor(nbrVoter, "Proposer", _agToken) {
        _angleGovernor = angleGovernor;
        proposalStore = _proposalStore;
        veANGLEDelegation = _veANGLEDelegation;
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

    function shortCircuit(uint256 proposalId) public useActor(1) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        Proposal memory proposal = proposalStore.getRandomProposal(proposalId);
        uint256 proposalHash =
            _angleGovernor.hashProposal(proposal.target, proposal.value, proposal.data, proposal.description);
        IGovernor.ProposalState currentState = _angleGovernor.state(proposalHash);
        if (currentState != IGovernor.ProposalState.Active) {
            return;
        }

        uint256 timeElapsed = _angleGovernor.votingDelay() + 1;
        uint256 blocksElapsed = (_angleGovernor.votingDelay() + 1) / 12;
        vm.warp(block.timestamp + timeElapsed);
        vm.roll(block.number + blocksElapsed + 1);

        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, _currentActor),
            abi.encode(_angleGovernor.shortCircuitThreshold(_angleGovernor.proposalSnapshot(proposalHash)) + 1)
        );
        _angleGovernor.castVote(proposalHash, 1);
        _angleGovernor.execute(proposal.target, proposal.value, proposal.data, proposal.description);
    }

    function execute(uint256 proposalId) public useActor(1) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        Proposal memory proposal = proposalStore.getRandomProposal(proposalId);
        uint256 proposalHash =
            _angleGovernor.hashProposal(proposal.target, proposal.value, proposal.data, proposal.description);
        uint256 proposalSnapshot = _angleGovernor.proposalSnapshot(proposalHash);
        vm.warp(_angleGovernor.proposalDeadline(proposalHash) + 1);
        vm.roll(_angleGovernor.$snapshotTimestampToSnapshotBlockNumber(proposalSnapshot) + 1);
        IGovernor.ProposalState currentState = _angleGovernor.state(proposalHash);
        if (currentState != IGovernor.ProposalState.Succeeded) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalHash,
                    currentState,
                    bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
                        | bytes32(1 << uint8(IGovernor.ProposalState.Queued))
                )
            );
        }
        _angleGovernor.execute(proposal.target, proposal.value, proposal.data, proposal.description);
        proposalStore.removeProposal(proposalHash);
        proposalStore.addOldProposal(proposal.target, proposal.value, proposal.data, proposal.description);
    }

    function skipVotingDelay() public useActor(1) {
        vm.warp(block.timestamp + _angleGovernor.votingDelay() + 1);
    }
}
