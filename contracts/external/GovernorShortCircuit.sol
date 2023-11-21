// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Checkpoints } from "oz/utils/structs/Checkpoints.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";
import { GovernorVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { GovernorVotesQuorumFraction } from "oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import { GovernorCountingFractional, SafeCast } from "./GovernorCountingFractional.sol";

import "../utils/Errors.sol";

/// @title GovernorShortCircuit
/// @notice Extends governor to pass propositions if the quorum is reached before the end of the voting period
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
//solhint-disable-next-line
/// @notice Taken from:
/// https://github.com/FraxFinance/frax-governance/blob/e465513ac282aa7bfd6744b3136354fae51fed3c/src/FraxGovernorBase.sol
abstract contract GovernorShortCircuit is GovernorVotes, GovernorCountingFractional, GovernorVotesQuorumFraction {
    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when governance changes the short circuit numerator
    /// @param oldShortCircuitNumerator The old short circuit numerator
    /// @param newShortCircuitNumerator The new contract address
    event ShortCircuitNumeratorUpdated(uint256 oldShortCircuitNumerator, uint256 newShortCircuitNumerator);

    /// @notice Emitted when governance changes the voting delay in blocks
    /// @param oldVotingDelayBlocks The old short circuit numerator
    /// @param newVotingDelayBlocks The new contract address
    event VotingDelayBlocksSet(uint256 oldVotingDelayBlocks, uint256 newVotingDelayBlocks);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Voting delay in number of blocks
    /// @dev only used to look up total veANGLE supply
    uint256 public $votingDelayBlocks;
    /// @notice Checkpoints for short circuit numerator
    /// mirroring _quorumNumeratorHistory from GovernorVotesQuorumFraction.sol
    Checkpoints.Trace224 private _$shortCircuitNumeratorHistory;
    /// @notice Lookup from snapshot timestamp to corresponding snapshot block number, used for quorum
    mapping(uint256 snapshot => uint256 blockNumber) public $snapshotTimestampToSnapshotBlockNumber;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(uint256 initialShortCircuitNumerator, uint256 initialVotingDelayBlocks) {
        _updateShortCircuitNumerator(initialShortCircuitNumerator);
        _setVotingDelayBlocks(initialVotingDelayBlocks);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    VIEW FUNCTIONS                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the latest short circuit numerator
    /// @dev Mirrors ```GovernorVotesQuorumFraction::quorumNumerator()```
    /// @return latestShortCircuitNumerator The short circuit numerator
    function shortCircuitNumerator() public view returns (uint256 latestShortCircuitNumerator) {
        latestShortCircuitNumerator = _$shortCircuitNumeratorHistory.latest();
    }

    /// @notice Returns the short circuit numerator at ```timepoint```
    /// @dev Mirrors ```GovernorVotesQuorumFraction::quorumNumerator(uint256 timepoint)```
    /// @param timepoint A block.number
    /// @return shortCircuitNumeratorAtTimepoint Short circuit numerator
    function shortCircuitNumerator(uint256 timepoint) public view returns (uint256 shortCircuitNumeratorAtTimepoint) {
        // If history is empty, fallback to old storage
        uint256 length = _$shortCircuitNumeratorHistory._checkpoints.length;

        // Optimistic search, check the latest checkpoint
        Checkpoints.Checkpoint224 memory latest = _$shortCircuitNumeratorHistory._checkpoints[length - 1];
        if (latest._key <= timepoint) {
            shortCircuitNumeratorAtTimepoint = latest._value;
            return shortCircuitNumeratorAtTimepoint;
        }

        // Otherwise, do the binary search
        shortCircuitNumeratorAtTimepoint = _$shortCircuitNumeratorHistory.upperLookupRecent(
            SafeCast.toUint32(timepoint)
        );
    }

    /// @notice Returns the latest short circuit numerator
    /// @dev Only supports historical quorum values for proposals that actually exist at ```timepoint```
    /// @param timepoint A block.number corresponding to a proposal snapshot
    /// @return shortCircuitThresholdAtTimepoint Total voting weight needed for short circuit to succeed
    function shortCircuitThreshold(uint256 timepoint) public view returns (uint256 shortCircuitThresholdAtTimepoint) {
        uint256 snapshotBlockNumber = $snapshotTimestampToSnapshotBlockNumber[timepoint];
        if (snapshotBlockNumber == 0 || snapshotBlockNumber >= block.number) revert InvalidTimepoint();

        shortCircuitThresholdAtTimepoint =
            (token().getPastTotalSupply(snapshotBlockNumber) * shortCircuitNumerator(timepoint)) /
            quorumDenominator();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @param newShortCircuitNumerator Number expressed as x/100 (percentage)
    function updateShortCircuitNumerator(uint256 newShortCircuitNumerator) external onlyGovernance {
        _updateShortCircuitNumerator(newShortCircuitNumerator);
    }

    /// @notice Changes the amount of blocks before the voting snapshot
    function setVotingDelayBlocks(uint256 newVotingDelayBlocks) external onlyGovernance {
        _setVotingDelayBlocks(newVotingDelayBlocks);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNALS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Called by state() to check for early proposal success or failure
    /// @param proposalId Proposal ID
    /// @return isShortCircuitFor Represents if short circuit threshold for votes were reached or not
    /// @return isShortCircuitAgainst Represents if short circuit threshold against votes were reached or not
    function _shortCircuit(
        uint256 proposalId
    ) internal view returns (bool isShortCircuitFor, bool isShortCircuitAgainst) {
        (uint256 againstVoteWeight, uint256 forVoteWeight, ) = proposalVotes(proposalId);

        uint256 proposalVoteStart = proposalSnapshot(proposalId);
        uint256 shortCircuitThresholdValue = shortCircuitThreshold(proposalVoteStart);
        isShortCircuitFor = forVoteWeight > shortCircuitThresholdValue;
        isShortCircuitAgainst = againstVoteWeight > shortCircuitThresholdValue;
    }

    /// @notice Called by governance to change the short circuit numerator
    /// @dev Mirrors ```GovernorVotesQuorumFraction::_updateQuorumNumerator(uint256 newQuorumNumerator)```
    /// @param newShortCircuitNumerator New short circuit numerator value
    function _updateShortCircuitNumerator(uint256 newShortCircuitNumerator) internal {
        // Numerator must be less than or equal to denominator
        if (newShortCircuitNumerator > quorumDenominator()) {
            revert ShortCircuitNumeratorGreaterThanQuorumDenominator();
        }

        uint256 oldShortCircuitNumerator = shortCircuitNumerator();

        // Set new quorum for future proposals
        _$shortCircuitNumeratorHistory.push(SafeCast.toUint32(clock()), SafeCast.toUint224(newShortCircuitNumerator));

        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitNumerator: oldShortCircuitNumerator,
            newShortCircuitNumerator: newShortCircuitNumerator
        });
    }

    /// @notice Called by governance to change the voting delay in blocks
    /// @notice This must be changed in tandem with ```votingDelay``` to properly set quorum values
    /// @param votingDelayBlocks New voting delay in blocks value
    function _setVotingDelayBlocks(uint256 votingDelayBlocks) internal {
        uint256 oldVotingDelayBlocks = $votingDelayBlocks;
        $votingDelayBlocks = votingDelayBlocks;
        emit VotingDelayBlocksSet({
            oldVotingDelayBlocks: oldVotingDelayBlocks,
            newVotingDelayBlocks: votingDelayBlocks
        });
    }
}
