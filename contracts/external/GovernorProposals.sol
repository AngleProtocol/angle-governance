// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Governor } from "oz/governance/Governor.sol";

import "../utils/Errors.sol";

/**
 * @notice Extension of {Governor} with `internal` and not `private` _proposals
 */
abstract contract GovernorProposals is Governor {
    mapping(uint256 proposalId => ProposalCore) internal _proposals;

    /// @inheritdoc Governor
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart;
    }

    /// @inheritdoc Governor
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart + _proposals[proposalId].voteDuration;
    }

    /// @inheritdoc Governor
    function proposalProposer(uint256 proposalId) public view virtual override returns (address) {
        return _proposals[proposalId].proposer;
    }

    /// @inheritdoc Governor
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].etaSeconds;
    }
}
