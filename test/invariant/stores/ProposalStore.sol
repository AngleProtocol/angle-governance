// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {StdUtils} from "forge-std/StdUtils.sol";

struct Proposal {
    address[] target;
    uint256[] value;
    bytes[] data;
    bytes32 description;
}

/// @dev Because Foundry does not commit the state changes between invariant runs, we need to
/// save the current timestamp in a contract with persistent storage.
contract ProposalStore is StdUtils {
    Proposal[] internal proposals;
    Proposal[] internal oldProposals;

    constructor() {}

    function addProposal(address[] memory target, uint256[] memory value, bytes[] memory data, bytes32 description)
        external
    {
        proposals.push(Proposal({target: target, value: value, data: data, description: description}));
    }

    function addOldProposal(address[] memory target, uint256[] memory value, bytes[] memory data, bytes32 description)
        external
    {
        oldProposals.push(Proposal({target: target, value: value, data: data, description: description}));
    }

    function removeProposal(uint256 proposalHash) external {
        for (uint256 i = 0; i < proposals.length; i++) {
            uint256 proposalId = uint256(
                keccak256(
                    abi.encode(proposals[i].target, proposals[i].value, proposals[i].data, proposals[i].description)
                )
            );
            if (proposalId == proposalHash) {
                proposals[i] = proposals[proposals.length - 1];
                proposals.pop();
                return;
            }
        }
    }

    function nbProposals() external view returns (uint256) {
        return proposals.length;
    }

    function getRandomProposal(uint256 seed) external view returns (Proposal memory) {
        return proposals[bound(seed, 0, proposals.length - 1)];
    }

    function getProposals() external view returns (Proposal[] memory) {
        return proposals;
    }

    function doesOldProposalExists(uint256 proposalHash) external view returns (bool) {
        for (uint256 i = 0; i < oldProposals.length; i++) {
            uint256 proposalId = uint256(
                keccak256(
                    abi.encode(
                        oldProposals[i].target, oldProposals[i].value, oldProposals[i].data, oldProposals[i].description
                    )
                )
            );
            if (proposalId == proposalHash) {
                return true;
            }
        }
        return false;
    }
}
