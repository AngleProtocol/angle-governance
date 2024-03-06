// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IVotes} from "oz-v5/governance/utils/IVotes.sol";

import {Governor} from "oz-v5/governance/Governor.sol";
import {GovernorPreventLateQuorum} from "oz-v5/governance/extensions/GovernorPreventLateQuorum.sol";
import {GovernorVotesQuorumFraction, GovernorVotes} from "oz-v5/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorSettings} from "oz-v5/governance/extensions/GovernorSettings.sol";
import {IERC5805} from "oz-v5/interfaces/IERC5805.sol";

import {GovernorCountingFractional} from "./external/GovernorCountingFractional.sol";
import {GovernorShortCircuit} from "./external/GovernorShortCircuit.sol";

import "./utils/Errors.sol";

/// @title AngleGovernor
/// @author Angle Labs, Inc
/// @dev Core of Angle governance system, extending various OpenZeppelin modules
/// @dev This contract overrides some OpenZeppelin functions, like those in `GovernorSettings` to introduce
/// the `onlyGovernance` modifier which ensures that only the Timelock contract can update the system's parameters
/// @dev The time parameters (`votingDelay`, `votingPeriod`, ...) are expressed here in timestamp units, but the
/// contract also has a `votingDelayBlocks` parameter which must be set in accordance to the `votingDelay` that is
/// used when computing quorums and whether proposals can be shortcircuited
/// @custom:security-contact contact@angle.money
contract AngleGovernor is
    GovernorSettings,
    GovernorPreventLateQuorum,
    GovernorCountingFractional,
    GovernorVotesQuorumFraction,
    GovernorShortCircuit
{
    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event TimelockChange(address indexed oldTimelock, address indexed newTimelock);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Timelock address that owns this contract and can change the system's parameters
    address public timelock;
    /// @notice Address where veANGLE holders can delegate their vote
    IERC5805 public veANGLEVotingDelegation;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        IVotes _token,
        address timelockAddress,
        uint48 initialVotingDelay,
        uint32 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint48 initialVoteExtension,
        uint256 initialQuorumNumerator,
        uint256 initialShortCircuitNumerator,
        uint256 initialVotingDelayBlocks
    )
        Governor("AngleGovernor")
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorPreventLateQuorum(initialVoteExtension)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(initialQuorumNumerator)
        GovernorShortCircuit(initialShortCircuitNumerator, initialVotingDelayBlocks)
    {
        _updateTimelock(timelockAddress);
        veANGLEVotingDelegation = IERC5805(address(_token));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  EXTERNAL OVERRIDES                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc Governor
    // solhint-disable-next-line
    /// @notice Base implementation taken from Frax Finance: https://github.com/FraxFinance/frax-governance/blob/e465513ac282aa7bfd6744b3136354fae51fed3c/src/FraxGovernorAlpha.sol
    /// @dev In this governor implementation, the owner of the contract is a Timelock contract. Yet not all proposals
    /// have to go through the Timelock contract, and so proposals may appear as executed when in fact they are
    /// queued in a timelock
    function state(uint256 proposalId) public view override(Governor) returns (ProposalState) {
        ProposalState currentState = super.state(proposalId);
        if (
            currentState == ProposalState.Executed || currentState == ProposalState.Canceled
                || currentState == ProposalState.Pending
        ) return currentState;

        uint256 snapshot = proposalSnapshot(proposalId);
        if ($snapshotTimestampToSnapshotBlockNumber[snapshot] >= block.number) return ProposalState.Pending;

        // Allow early execution when overwhelming majority
        (bool isShortCircuitFor, bool isShortCircuitAgainst) = _shortCircuit(proposalId);
        if (isShortCircuitFor) {
            return ProposalState.Succeeded;
        } else if (isShortCircuitAgainst) {
            return ProposalState.Defeated;
        } else {
            return currentState;
        }
    }

    /// @inheritdoc GovernorVotesQuorumFraction
    function quorum(uint256 timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256 quorumAtTimepoint)
    {
        uint256 snapshotBlockNumber = $snapshotTimestampToSnapshotBlockNumber[timepoint];
        if (snapshotBlockNumber == 0 || snapshotBlockNumber >= block.number) revert InvalidTimepoint();

        quorumAtTimepoint =
            (token().getPastTotalSupply(snapshotBlockNumber) * quorumNumerator(timepoint)) / quorumDenominator();
    }

    /// @inheritdoc GovernorPreventLateQuorum
    function proposalDeadline(uint256 proposalId)
        public
        view
        override(Governor, GovernorPreventLateQuorum)
        returns (uint256)
    {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }

    /// @inheritdoc GovernorSettings
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }

    /// @inheritdoc GovernorVotes
    function token() public view override(GovernorVotes) returns (IERC5805) {
        return veANGLEVotingDelegation;
    }

    /// @inheritdoc GovernorVotes
    // solhint-disable-next-line
    function CLOCK_MODE() public pure override(GovernorVotes, Governor) returns (string memory) {
        return "mode=timestamp";
    }

    /// @inheritdoc GovernorVotes
    function clock() public view override(GovernorVotes, Governor) returns (uint48) {
        return uint48(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  INTERNAL OVERRIDES                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc Governor
    // solhint-disable-next-line
    /// @notice Base implementation taken from Frax Finance: https://github.com/FraxFinance/frax-governance/blob/e465513ac282aa7bfd6744b3136354fae51fed3c/src/FraxGovernorAlpha.sol
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(Governor) returns (uint256 proposalId) {
        proposalId = super._propose(targets, values, calldatas, description, proposer);

        // cf Frax Finance contracts
        // Save the block number of the snapshot, so it can be later used to fetch the total outstanding supply
        // of veANGLE. We did this so we can still support quorum(timestamp), without breaking the OZ standard.
        // The underlying issue is that VE_ANGLE.totalSupply(timestamp) doesn't work for historical values, so we must
        // use VE_ANGLE.totalSupply(), or VE_ANGLE.totalSupplyAt(blockNumber).
        uint256 snapshot = proposalSnapshot(proposalId);
        $snapshotTimestampToSnapshotBlockNumber[snapshot] = block.number + $votingDelayBlocks;
    }

    /// @inheritdoc GovernorPreventLateQuorum
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        override(Governor, GovernorPreventLateQuorum)
        returns (uint256)
    {
        return GovernorPreventLateQuorum._castVote(proposalId, account, support, reason, params);
    }

    /// @inheritdoc Governor
    function _executor() internal view override(Governor) returns (address) {
        return timelock;
    }

    /// @inheritdoc Governor
    function _checkGovernance() internal view override(Governor) {
        if (msg.sender != _executor()) revert NotExecutor();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTER                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Public endpoint to update the underlying timelock instance. Restricted to the timelock itself,
    /// so updates must be proposed, scheduled, and executed through governance proposals.
    /// @dev It is not recommended to change the timelock while there are other queued governance proposals.
    function updateTimelock(address newTimelock) external virtual onlyGovernance {
        _updateTimelock(newTimelock);
    }

    function _updateTimelock(address newTimelock) internal {
        if (newTimelock == address(0)) revert ZeroAddress();
        emit TimelockChange(timelock, newTimelock);
        timelock = newTimelock;
    }
}
