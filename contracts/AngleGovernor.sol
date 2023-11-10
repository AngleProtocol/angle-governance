// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IVotes } from "oz/governance/utils/IVotes.sol";

import { Governor, SafeCast } from "oz/governance/Governor.sol";
import { GovernorVotesQuorumFraction, GovernorVotes } from "oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import { GovernorSettings } from "oz/governance/extensions/GovernorSettings.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";

import { GovernorProposals } from "./external/GovernorProposals.sol";
import { GovernorPreventLateQuorum } from "./external/GovernorPreventLateQuorum.sol";
import { GovernorToken } from "./external/GovernorToken.sol";
import { GovernorCountingFractional } from "./external/GovernorCountingFractional.sol";
import { GovernorShortCircuit } from "./external/GovernorShortCircuit.sol";

import "./utils/Errors.sol";

/// @title AngleGovernor
/// @author Angle Labs, Inc
/// @dev Core of Angle governance system, extending various OpenZeppelin modules
/// @dev This contract overrides some OpenZeppelin function, like those in `GovernorSettings` to introduce
/// the `onlyExecutor` modifier which ensures that only the Timelock contract can update the system's parameters
/// @dev The time parameters (`votingDelay`, `votingPeriod`, ...) are expressed here in timestamp units, but the
/// also has a `votingDelayBlocks` parameters which must be set in accordance to the `votingDelay`
/// @dev The `state` and `propose` functions here were forked from FRAX governance implementation
/// @custom:security-contact contact@angle.money
contract AngleGovernor is
    GovernorSettings,
    GovernorToken,
    GovernorProposals,
    GovernorPreventLateQuorum,
    GovernorCountingFractional,
    GovernorVotesQuorumFraction,
    GovernorShortCircuit
{
    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event TimelockChange(address oldTimelock, address newTimelock);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    TimelockController private _timelock;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIER                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the sender is the system's executor
    modifier onlyExecutor() {
        if (msg.sender != _executor()) revert NotExecutor();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        IVotes _token,
        TimelockController timelockAddress,
        uint48 initialVotingDelay,
        uint32 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint48 initialVoteExtension,
        uint256 initialQuorumNumerator,
        uint256 initialShortCircuitNumerator,
        uint256 initialVotingDelayBlocks
    )
        Governor("AngleGovernor")
        GovernorToken(_token)
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorPreventLateQuorum(initialVoteExtension)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(initialQuorumNumerator)
        GovernorShortCircuit(initialShortCircuitNumerator, initialVotingDelayBlocks)
    {
        _updateTimelock(timelockAddress);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    VIEW FUNCTIONS                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Timelock address that owns this contract and can change the system's parameters
    function timelock() public view returns (address) {
        return address(_timelock);
    }

    function _executor() internal view override(Governor) returns (address) {
        return address(_timelock);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Public endpoint to update the underlying timelock instance. Restricted to the timelock itself,
    /// so updates must be proposed, scheduled, and executed through governance proposals.
    /// @dev It is not recommended to change the timelock while there are other queued governance proposals.
    function updateTimelock(TimelockController newTimelock) external virtual onlyExecutor {
        _updateTimelock(newTimelock);
    }

    /// @param veANGLEVotingDelegation New IERC5805 veANGLEVotingDelegation contract address
    function setVeANGLEVotingDelegation(address veANGLEVotingDelegation) external onlyExecutor {
        _setVeANGLEVotingDelegation(veANGLEVotingDelegation);
    }

    /// @param newShortCircuitNumerator Number expressed as x/100 (percentage)
    function updateShortCircuitNumerator(uint256 newShortCircuitNumerator) external onlyExecutor {
        _updateShortCircuitNumerator(newShortCircuitNumerator);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       OVERRIDES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc Governor
    // solhint-disable-next-line
    /// @notice Fork from Frax Finance: https://github.com/FraxFinance/frax-governance/blob/e465513ac282aa7bfd6744b3136354fae51fed3c/src/FraxGovernorAlpha.sol
    function state(uint256 proposalId) public view override returns (ProposalState) {
        // We read the struct fields into the stack at once so Solidity emits a single SLOAD
        ProposalCore storage proposal = _proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert GovernorNonexistentProposal(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint || $snapshotTimestampToSnapshotBlockNumber[snapshot] >= block.number) {
            return ProposalState.Pending;
        }

        // Allow early execution when overwhelming majority
        (bool isShortCircuitFor, bool isShortCircuitAgainst) = _shortCircuit(proposalId);
        if (isShortCircuitFor) {
            return ProposalState.Succeeded;
        } else if (isShortCircuitAgainst) {
            return ProposalState.Defeated;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        } else if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        } else if (proposalEta(proposalId) == 0) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Queued;
        }
    }

    /// @inheritdoc Governor
    // solhint-disable-next-line
    /// @notice Fork from Frax Finance: https://github.com/FraxFinance/frax-governance/blob/e465513ac282aa7bfd6744b3136354fae51fed3c/src/FraxGovernorAlpha.sol
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        if (targets.length != values.length || targets.length != calldatas.length || targets.length == 0) {
            revert GovernorInvalidProposalLength(targets.length, calldatas.length, values.length);
        }
        if (_proposals[proposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState(proposalId, state(proposalId), bytes32(0));
        }

        uint256 snapshot = clock() + votingDelay();
        uint256 duration = votingPeriod();

        ProposalCore storage proposal = _proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(duration);

        // cf Frax Finance contracts
        // Save the block number of the snapshot, so it can be later used to fetch the total outstanding supply
        // of veANGLE. We did this so we can still support quorum(timestamp), without breaking the OZ standard.
        // The underlying issue is that VE_ANGLE.totalSupply(timestamp) doesn't work for historical values, so we must
        // use VE_ANGLE.totalSupply(), or VE_ANGLE.totalSupplyAt(blockNumber).
        $snapshotTimestampToSnapshotBlockNumber[snapshot] = block.number + $votingDelayBlocks;

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            snapshot + duration,
            description
        );

        // Using a named return variable to avoid stack too deep errors
    }

    /// @inheritdoc GovernorVotesQuorumFraction
    function quorum(
        uint256 timepoint
    ) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256 quorumAtTimepoint) {
        uint256 snapshotBlockNumber = $snapshotTimestampToSnapshotBlockNumber[timepoint];
        if (snapshotBlockNumber == 0 || snapshotBlockNumber >= block.number) revert InvalidTimepoint();

        quorumAtTimepoint =
            (token().getPastTotalSupply(snapshotBlockNumber) * quorumNumerator(timepoint)) /
            quorumDenominator();
    }

    /// @inheritdoc GovernorPreventLateQuorum
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override(Governor, GovernorPreventLateQuorum) returns (uint256) {
        return GovernorPreventLateQuorum._castVote(proposalId, account, support, reason, params);
    }

    /// @inheritdoc GovernorPreventLateQuorum
    function proposalDeadline(
        uint256 proposalId
    ) public view override(Governor, GovernorProposals, GovernorPreventLateQuorum) returns (uint256) {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }

    /// @inheritdoc GovernorVotesQuorumFraction
    function updateQuorumNumerator(uint256 newQuorumNumerator) external override onlyExecutor {
        _updateQuorumNumerator(newQuorumNumerator);
    }

    /// @inheritdoc GovernorPreventLateQuorum
    function setLateQuorumVoteExtension(uint48 newVoteExtension) public override onlyExecutor {
        _setLateQuorumVoteExtension(newVoteExtension);
    }

    /// @inheritdoc GovernorSettings
    function setVotingDelay(uint48 newVotingDelay) public override onlyExecutor {
        _setVotingDelay(newVotingDelay);
    }

    /// @inheritdoc GovernorSettings
    function setVotingPeriod(uint32 newVotingPeriod) public override onlyExecutor {
        _setVotingPeriod(newVotingPeriod);
    }

    /// @inheritdoc GovernorSettings
    function setProposalThreshold(uint256 newProposalThreshold) public override onlyExecutor {
        _setProposalThreshold(newProposalThreshold);
    }

    /// @inheritdoc GovernorSettings
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingDelay();
    }

    /// @inheritdoc GovernorSettings
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingPeriod();
    }

    /// @inheritdoc GovernorSettings
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }

    /// @inheritdoc Governor
    function proposalSnapshot(
        uint256 proposalId
    ) public view virtual override(Governor, GovernorProposals) returns (uint256) {
        return GovernorProposals.proposalSnapshot(proposalId);
    }

    /// @inheritdoc Governor
    function proposalProposer(
        uint256 proposalId
    ) public view virtual override(Governor, GovernorProposals) returns (address) {
        return GovernorProposals.proposalProposer(proposalId);
    }

    /// @inheritdoc Governor
    function proposalEta(
        uint256 proposalId
    ) public view virtual override(Governor, GovernorProposals) returns (uint256) {
        return GovernorProposals.proposalEta(proposalId);
    }

    /// @inheritdoc GovernorVotes
    function token() public view override(GovernorToken, GovernorVotes) returns (IERC5805) {
        return GovernorToken.token();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNALS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _updateTimelock(TimelockController newTimelock) private {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }
}
