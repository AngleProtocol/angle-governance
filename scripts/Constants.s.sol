// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";

enum ContractType {
    Timelock,
    ProposalSender,
    Governor,
    ProposalReceiver,
    TreasuryAgEUR,
    StEUR,
    TransmuterAgEUR,
    CoreBorrow,
    GovernorMultisig,
    GuardianMultisig,
    ProxyAdmin,
    Angle,
    veANGLE,
    SmartWalletWhitelist,
    veBoostProxy,
    GaugeController,
    AngleDistributor,
    AngleMiddleman,
    FeeDistributor
}

uint256 constant timelockDelay = 1 days;
uint48 constant initialVotingDelay = 1 days;
uint256 constant initialVotingDelayBlocks = 1 days / 12;
uint32 constant initialVotingPeriod = 4 days;
uint256 constant initialProposalThreshold = 100_000e18;
uint48 constant initialVoteExtension = 3 hours;

// TODO: update so we deploy with small values and later increase back up
uint256 constant initialQuorumNumerator = 5;
uint256 constant initialShortCircuitNumerator = 10;
bytes constant nullBytes = hex"";

uint256 constant CHAIN_ETHEREUM = 1;
uint256 constant CHAIN_ARBITRUM = 42161;
uint256 constant CHAIN_AVALANCHE = 43114;
uint256 constant CHAIN_OPTIMISM = 10;
uint256 constant CHAIN_POLYGON = 137;
uint256 constant CHAIN_GNOSIS = 100;
uint256 constant CHAIN_BNB = 56;
uint256 constant CHAIN_CELO = 42220;
uint256 constant CHAIN_ZKEVMPOLYGON = 1101;
uint256 constant CHAIN_BASE = 8453;
uint256 constant CHAIN_LINEA = 59144;
uint256 constant CHAIN_MANTLE = 5000;
uint256 constant CHAIN_AURORA = 1313161554;
