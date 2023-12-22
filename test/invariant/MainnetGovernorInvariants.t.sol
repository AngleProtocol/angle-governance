// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { Voter } from "./actors/Voter.t.sol";
import { Proposer } from "./actors/Proposer.t.sol";
import { BadVoter } from "./actors/BadVoter.t.sol";
import { Fixture, AngleGovernor } from "../Fixture.t.sol";
import { ProposalStore, Proposal } from "./stores/ProposalStore.sol";
import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimestampStore } from "./stores/TimestampStore.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract MainnetGovernorInvariants is Fixture {
    uint256 internal constant _NUM_VOTER = 10;

    Voter internal _voterHandler;
    Proposer internal _proposerHandler;
    BadVoter internal _badVoterHandler;

    // Keep track of current proposals
    ProposalStore internal _proposalStore;
    TimestampStore internal _timestampStore;

    modifier useCurrentTimestampBlock() {
        vm.warp(_timestampStore.currentTimestamp());
        vm.roll(_timestampStore.currentBlockNumber());
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        _proposalStore = new ProposalStore();
        _timestampStore = new TimestampStore();
        _voterHandler = new Voter(angleGovernor, ANGLE, _NUM_VOTER, _proposalStore);
        _proposerHandler = new Proposer(angleGovernor, ANGLE, 1, _proposalStore, token, _timestampStore);
        _badVoterHandler = new BadVoter(angleGovernor, ANGLE, _NUM_VOTER, _proposalStore);

        // Label newly created addresses
        vm.label({ account: address(_proposalStore), newLabel: "ProposalStore" });
        for (uint256 i; i < _NUM_VOTER; i++) {
            vm.label(_voterHandler.actors(i), string.concat("Voter ", Strings.toString(i)));
            _setupDealAndLockANGLE(_voterHandler.actors(i), 100000000e18, 4 * 365 days);
        }
        for (uint256 i; i < _NUM_VOTER; i++) {
            vm.label(_badVoterHandler.actors(i), string.concat("BadVoter ", Strings.toString(i)));
            _setupDealAndLockANGLE(_badVoterHandler.actors(i), 100000000e18, 4 * 365 days);
        }
        vm.label(_proposerHandler.actors(0), "Proposer");
        _setupDealAndLockANGLE(_proposerHandler.actors(0), angleGovernor.proposalThreshold() * 10, 4 * 365 days);

        vm.warp(block.timestamp + 1 weeks);

        targetContract(address(_voterHandler));
        targetContract(address(_proposerHandler));
        targetContract(address(_badVoterHandler));

        // Set the right snapshot block number for the current timestamp
        vm.warp(angleGovernor.$snapshotTimestampToSnapshotBlockNumber(block.timestamp));

        {
            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = Voter.vote.selector;
            targetSelector(FuzzSelector({ addr: address(_voterHandler), selectors: selectors }));
        }
        {
            bytes4[] memory selectors = new bytes4[](4);
            selectors[0] = Proposer.propose.selector;
            selectors[1] = Proposer.execute.selector;
            selectors[2] = Proposer.tryToExecute.selector;
            selectors[3] = Proposer.skipVotingDelay.selector;
            targetSelector(FuzzSelector({ addr: address(_proposerHandler), selectors: selectors }));
        }
        {
            bytes4[] memory selectors = new bytes4[](3);
            selectors[0] = BadVoter.voteNonExistantProposal.selector;
            selectors[1] = BadVoter.queueNewlyCreatedProposal.selector;
            selectors[2] = BadVoter.executeNonReadyProposals.selector;
            targetSelector(FuzzSelector({ addr: address(_badVoterHandler), selectors: selectors }));
        }
    }

    function invariant_VotesUnderTotalsupply() public useCurrentTimestampBlock {
        uint256 proposalLength = _proposalStore.nbProposals();
        Proposal[] memory proposals = _proposalStore.getProposals();
        for (uint256 i; i < proposalLength; i++) {
            Proposal memory proposal = proposals[i];
            uint256 proposalHash = angleGovernor.hashProposal(
                proposal.target,
                proposal.value,
                proposal.data,
                proposal.description
            );
            uint256 totalSupply = ANGLE.totalSupply();
            (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = angleGovernor.proposalVotes(proposalHash);
            assertLe(againstVotes + forVotes + abstainVotes, totalSupply, "Votes should be under total supply");
        }
    }

    function invariant_ProposalsCorrectState() public useCurrentTimestampBlock {
        uint256 proposalLength = _proposalStore.nbProposals();
        Proposal[] memory proposals = _proposalStore.getProposals();
        for (uint256 i; i < proposalLength; i++) {
            Proposal memory proposal = proposals[i];
            uint256 proposalHash = angleGovernor.hashProposal(
                proposal.target,
                proposal.value,
                proposal.data,
                proposal.description
            );
            IGovernor.ProposalState currentState = angleGovernor.state(proposalHash);
            uint256 snapshot = angleGovernor.proposalSnapshot(proposalHash);
            uint256 deadline = angleGovernor.proposalDeadline(proposalHash);
            console.log(block.number);
            uint256 quorum = angleGovernor.quorum(snapshot);
            (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = angleGovernor.proposalVotes(proposalHash);
            uint256 shortCircuitThreshold = angleGovernor.shortCircuitThreshold(snapshot);
            if (snapshot >= block.number - 1) {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Pending), "Proposal should be pending");
            } else if (deadline < block.timestamp && forVotes <= shortCircuitThreshold) {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Active), "Proposal should be active");
            } else if (forVotes >= shortCircuitThreshold) {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Succeeded), "Proposal should be succeeded");
            } else if (againstVotes >= shortCircuitThreshold) {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Defeated), "Proposal should be defeated");
            } else if (
                forVotes > againstVotes && forVotes > abstainVotes && forVotes + againstVotes + abstainVotes >= quorum
            ) {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Succeeded), "Proposal should be succeeded");
            } else if (block.timestamp >= deadline) {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Defeated), "Proposal should be defeated");
            } else {
                assertEq(uint8(currentState), uint8(IGovernor.ProposalState.Queued), "Proposal should be queued");
            }
        }
    }

    function invariant_CannotExecuteTwiceProposal() public useCurrentTimestampBlock {
        Proposal[] memory oldProposals = _proposalStore.getOldProposals();
        for (uint256 i; i < oldProposals.length; i++) {
            Proposal memory proposal = oldProposals[i];
            uint256 proposalHash = angleGovernor.hashProposal(
                proposal.target,
                proposal.value,
                proposal.data,
                proposal.description
            );
            IGovernor.ProposalState currentState = angleGovernor.state(proposalHash);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalHash,
                    currentState,
                    bytes32(1 << uint8(IGovernor.ProposalState.Succeeded)) |
                        bytes32(1 << uint8(IGovernor.ProposalState.Queued))
                )
            );
            angleGovernor.execute(proposal.target, proposal.value, proposal.data, proposal.description);
        }
    }

    function invariant_CannotVoteExecutedProposal() public useCurrentTimestampBlock {
        Proposal[] memory oldProposals = _proposalStore.getOldProposals();
        for (uint256 i; i < oldProposals.length; i++) {
            Proposal memory proposal = oldProposals[i];
            uint256 proposalHash = angleGovernor.hashProposal(
                proposal.target,
                proposal.value,
                proposal.data,
                proposal.description
            );
            IGovernor.ProposalState currentState = angleGovernor.state(proposalHash);
            if (currentState != IGovernor.ProposalState.Active) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IGovernor.GovernorUnexpectedProposalState.selector,
                        proposalHash,
                        currentState,
                        bytes32(1 << uint8(IGovernor.ProposalState.Active))
                    )
                );
                angleGovernor.castVote(proposalHash, 1);
            }
        }
    }
}
