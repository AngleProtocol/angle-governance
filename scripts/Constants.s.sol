// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";

/*
uint256 constant timelockDelay = 1 days;
uint48 constant initialVotingDelay = 1 days;
uint256 constant initialVotingDelayBlocks = 1 days / 12;
uint32 constant initialVotingPeriod = 4 days;
uint256 constant initialProposalThreshold = 100_000e18;
uint48 constant initialVoteExtension = 3 hours;
*/

uint256 constant timelockDelayTest = 300;
uint48 constant initialVotingDelayTest = 300;
uint256 constant initialVotingDelayBlocksTest = 60;
uint32 constant initialVotingPeriodTest = 3600;
uint256 constant initialProposalThresholdTest = 100_000e18;
uint48 constant initialVoteExtensionTest = 60;

// TODO: update so we deploy with small values and later increase back up
uint256 constant initialQuorumNumerator = 20;
uint256 constant initialShortCircuitNumerator = 75;
bytes constant nullBytes = hex"";

address constant SAFE_MAINNET = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
// This is the guardian for testing purposes
address constant SAFE_GNOSIS = 0xf0A31faec2B4fC6396c65B1aF1F6A71E653f11F0;
address constant SAFE_POLYGON = 0x3b9D32D0822A6351F415BeaB05251c1457FF6f8D;

uint256 constant CHAIN_GNOSIS = 100;
uint256 constant CHAIN_POLYGON = 137;
uint256 constant CHAIN_OPTIMISM = 10;

// TODO update when deployed
// address constant proposalSender = address(0x499C86959a330Eb860FdFFf6e87896d4298a4F4E);
address constant proposalReceiverPolygon = address(0x060246eD061999F7e128Fd8355d84467d6726b71);
address constant timelockPolygon = address(0x0d17B69fF7D30F7EC13A9447d1E5624b601a730b);
