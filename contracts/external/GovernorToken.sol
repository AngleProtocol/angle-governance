// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IVotes } from "oz/governance/utils/IVotes.sol";
import { GovernorVotes, IERC5805 } from "oz/governance/extensions/GovernorVotes.sol";

/**
 * @notice Extension of {Governor} with `internal` and not `private` _token
 */
abstract contract GovernorToken is GovernorVotes {
    event VeANGLEVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);

    IERC5805 internal _token_;

    constructor(IVotes _token) {
        _setVeANGLEVotingDelegation(address(_token));
    }

    /// @inheritdoc GovernorVotes
    function token() public view virtual override returns (IERC5805) {
        return _token_;
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
