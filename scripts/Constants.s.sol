// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { ITransmuter } from "transmuter/interfaces/ITransmuter.sol";
import { IAgToken } from "borrow/interfaces/IAgToken.sol";
import { ProxyAdmin } from "oz/proxy/transparent/ProxyAdmin.sol";
import { Ownable } from "oz/access/Ownable.sol";
import { CoreBorrow } from "borrow/coreBorrow/CoreBorrow.sol";
import { ITreasury } from "borrow/interfaces/ITreasury.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import "./Interfaces.s.sol";

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

/*
uint256 constant timelockDelay = 1 days;
uint48 constant initialVotingDelay = 1 days;
uint256 constant initialVotingDelayBlocks = 1 days / 12;
uint32 constant initialVotingPeriod = 4 days;
uint256 constant initialProposalThreshold = 100_000e18;
uint48 constant initialVoteExtension = 3 hours;
*/

uint256 constant BASE_18 = 1e18;
uint256 constant BASE_9 = 1e9;

uint64 constant twoPoint5Rate = 782997666703977344;
uint64 constant fourRate = 1243680713969297408;
uint64 constant fourPoint3Rate = 1335019428339023872;

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

uint256 constant CHAIN_ARBITRUM = 42161;
uint256 constant CHAIN_AVALANCHE = 43114;
uint256 constant CHAIN_ETHEREUM = 1;
uint256 constant CHAIN_OPTIMISM = 10;
uint256 constant CHAIN_POLYGON = 137;
uint256 constant CHAIN_GNOSIS = 100;
uint256 constant CHAIN_BNB = 56;
uint256 constant CHAIN_CELO = 42220;
uint256 constant CHAIN_POLYGONZKEVM = 1101;
uint256 constant CHAIN_BASE = 8453;
uint256 constant CHAIN_LINEA = 59144;
uint256 constant CHAIN_MANTLE = 5000;
uint256 constant CHAIN_AURORA = 1313161554;

// TODO update when deployed
// address constant proposalSender = address(0x499C86959a330Eb860FdFFf6e87896d4298a4F4E);
address constant proposalReceiverPolygon = address(0x060246eD061999F7e128Fd8355d84467d6726b71);
address constant timelockPolygon = address(0x0d17B69fF7D30F7EC13A9447d1E5624b601a730b);

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  EXTERNAL CONTRACTS                                                
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

address constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
address constant BC3M = 0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7;

struct SubCall {
    uint256 chainId;
    address target;
    uint256 value;
    bytes data;
}
