// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import {ILayerZeroEndpoint} from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {IVotes} from "oz-v5/governance/extensions/GovernorVotes.sol";

uint48 constant initialVotingDelay = 1800;
uint32 constant initialVotingPeriod = 36000;
uint256 constant initialProposalThreshold = 100e18;
uint48 constant initialVoteExtension = 3600;
uint256 constant initialQuorumNumerator = 10;
uint256 constant initialShortCircuitNumerator = 50;
uint256 constant initialVotingDelayBlocks = 150;
uint256 constant totalVotes = 1e25;
bytes constant nullBytes = hex"";

address constant whale = 0xD13F8C25CceD32cdfA79EB5eD654Ce3e484dCAF5;
IVotes constant veANGLE = IVotes(0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5);
address constant mainnetMultisig = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
ILayerZeroEndpoint constant mainnetLzEndpoint = ILayerZeroEndpoint(0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675);
