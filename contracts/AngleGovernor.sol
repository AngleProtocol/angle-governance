// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IVotes } from "oz/governance/utils/IVotes.sol";

import { Governor, SafeCast } from "oz/governance/Governor.sol";
import { GovernorPreventLateQuorum } from "oz/governance/extensions/GovernorPreventLateQuorum.sol";
import { GovernorVotesQuorumFraction, GovernorVotes } from "oz/governance/extensions/GovernorVotesQuorumFraction.sol";
import { GovernorSettings } from "oz/governance/extensions/GovernorSettings.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";

import { GovernorCountingFractional } from "./external/GovernorCountingFractional.sol";
import { GovernorShortCircuit } from "./external/GovernorShortCircuit.sol";

import "./utils/Errors.sol";

/// @title AngleGovernor
/// @author Angle Labs, Inc
/// @dev Core of Angle governance system, extending various OpenZeppelin modules
/// @dev This contract overrides some OpenZeppelin function, like those in `GovernorSettings` to introduce
/// the `onlyExecutor` modifier which ensures that only the Timelock contract can update the system's parameters
/// @dev The time parameters (`votingDelay`, `votingPeriod`, ...) are expressed here in block number units which
///  means that this implementation is only suited for an Ethereum deployment
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

    event TimelockChange(address oldTimelock, address newTimelock);
    event QuorumChange(uint256 oldQuorum, uint256 newQuorum);
    event VeANGLEVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    TimelockController private _timelock;
    IERC5805 internal _token_;

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
        TimelockController timelockAddress
    )
        Governor("AngleGovernor")
        GovernorSettings(1800 /* 30 mins */, 36000 /* 10 hours */, 100000e18)
        GovernorPreventLateQuorum(3600 /* 1 hour */)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(10)
        GovernorShortCircuit(50)
    {
        _updateTimelock(timelockAddress);
        _setVeANGLEVotingDelegation(address(_token));
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
    ) public view override(Governor, GovernorPreventLateQuorum) returns (uint256) {
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

    /// @inheritdoc GovernorVotes
    function clock() public view override(Governor, GovernorVotes) returns (uint48) {
        return SafeCast.toUint48(block.number);
    }

    /// @inheritdoc GovernorVotes
    function token() public view override returns (IERC5805) {
        return _token_;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNALS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _updateTimelock(TimelockController newTimelock) private {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }

    /// @param veANGLEVotingDelegation new IERC5805 VeANGLEVotingDelegation contract address
    function _setVeANGLEVotingDelegation(address veANGLEVotingDelegation) internal {
        address oldVeANGLEVotingDelegation = address(token());
        _token_ = IERC5805(veANGLEVotingDelegation);
        emit VeANGLEVotingDelegationSet({
            oldVotingDelegation: oldVeANGLEVotingDelegation,
            newVotingDelegation: veANGLEVotingDelegation
        });
    }
}
