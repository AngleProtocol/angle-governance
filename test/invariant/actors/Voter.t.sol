// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BaseActor, IERC20, IERC20Metadata, AngleGovernor, TestStorage} from "./BaseActor.t.sol";
import {console} from "forge-std/console.sol";
import {ProposalStore, Proposal} from "../stores/ProposalStore.sol";
import {IGovernor} from "oz-v5/governance/IGovernor.sol";

contract Voter is BaseActor {
    AngleGovernor internal _angleGovernor;
    ProposalStore public proposalStore;

    constructor(AngleGovernor angleGovernor, IERC20 angle, uint256 nbrVoter, ProposalStore _proposalStore)
        BaseActor(nbrVoter, "Voter", angle)
    {
        _angleGovernor = angleGovernor;
        proposalStore = _proposalStore;
    }

    function vote(uint256 proposalSeed, uint256 voteOutcome) public useActor(1) {
        if (proposalStore.nbProposals() == 0) {
            return;
        }
        voteOutcome = bound(voteOutcome, 0, 2);
        Proposal memory proposal = proposalStore.getRandomProposal(proposalSeed);
        uint256 proposalHash =
            _angleGovernor.hashProposal(proposal.target, proposal.value, proposal.data, proposal.description);
        IGovernor.ProposalState currentState = _angleGovernor.state(proposalHash);
        if (currentState != IGovernor.ProposalState.Active) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalHash,
                    currentState,
                    bytes32(1 << uint8(IGovernor.ProposalState.Active))
                )
            );
        }
        _angleGovernor.castVote(proposalHash, uint8(voteOutcome));
    }
}
