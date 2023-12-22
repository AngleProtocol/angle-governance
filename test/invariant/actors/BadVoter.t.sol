// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseActor, IERC20, IERC20Metadata, AngleGovernor, TestStorage } from "./BaseActor.t.sol";
import { console } from "forge-std/console.sol";
import { ProposalStore, Proposal } from "../stores/ProposalStore.sol";
import { IGovernor } from "oz/governance/IGovernor.sol";

contract BadVoter is BaseActor {
    AngleGovernor internal _angleGovernor;
    ProposalStore public proposalStore;

    constructor(
        AngleGovernor angleGovernor,
        IERC20 angle,
        uint256 nbrVoter,
        ProposalStore _proposalStore
    ) BaseActor(nbrVoter, "BadVoter", angle) {
        _angleGovernor = angleGovernor;
        proposalStore = _proposalStore;
    }

    function voteNonExistantProposal(uint256 actorIndexSeed, uint256 proposalId) public useActor(actorIndexSeed) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        Proposal[] memory proposals = proposalStore.getProposals();
        for (uint256 i; i < proposals.length; i++) {
            Proposal memory proposal = proposals[i];
            uint256 proposalHash = _angleGovernor.hashProposal(
                proposal.target,
                proposal.value,
                proposal.data,
                proposal.description
            );
            if (proposalHash != proposalId || proposalStore.doesOldProposalExists(proposalHash)) {
                return;
            }
        }

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorNonexistentProposal.selector, proposalId));
        _angleGovernor.castVote(proposalId, 1);
    }

    function executeNonReadyProposals(uint256 actorIndexSeed, uint256 proposalId) public useActor(actorIndexSeed) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        Proposal[] memory proposals = proposalStore.getProposals();
        Proposal memory proposal = proposalStore.getRandomProposal(proposalId);
        uint256 proposalHash = _angleGovernor.hashProposal(
            proposal.target,
            proposal.value,
            proposal.data,
            proposal.description
        );
        if (_angleGovernor.state(proposalHash) != IGovernor.ProposalState.Succeeded) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalHash,
                    _angleGovernor.state(proposalHash),
                    bytes32(1 << uint8(IGovernor.ProposalState.Succeeded)) |
                        bytes32(1 << uint8(IGovernor.ProposalState.Queued))
                )
            );
            _angleGovernor.execute(proposal.target, proposal.value, proposal.data, proposal.description);
        }
    }
}
