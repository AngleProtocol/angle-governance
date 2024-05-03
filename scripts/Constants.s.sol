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
import { TimelockController } from "oz/governance/TimelockController.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import "utils/src/Constants.sol";
import "./Interfaces.s.sol";

struct SubCall {
    uint256 chainId;
    address target;
    uint256 value;
    bytes data;
}

struct ChainContract {
    uint256 chainId;
    address token;
}

uint256 constant timelockDelay = 1 days;
uint48 constant initialVotingDelay = 1 days;
uint256 constant initialVotingDelayBlocks = 1 days / 12;
uint32 constant initialVotingPeriod = 4 days;
uint256 constant initialProposalThreshold = 100_000e18;
uint48 constant initialVoteExtension = 3 hours;

// TODO: increase quorum numbers back up
uint256 constant initialQuorumNumerator = 5;
uint256 constant initialShortCircuitNumerator = 10;
bytes constant nullBytes = hex"";

uint256 constant CHAIN_SOURCE = CHAIN_ETHEREUM;

uint256 constant BASE_GAS = 100000;
uint256 constant GAS_MULTIPLIER = 150000; // 1.5x

uint64 constant twoPoint5Rate = 782997666703977344;
uint64 constant fourRate = 1243680713969297408;
uint64 constant fourPoint3Rate = 1335019428339023872;

string constant pathProposal = "/scripts/proposals/payload.json";
address constant proposer = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185;
address constant whale = 0x41Bc7d0687e6Cea57Fa26da78379DfDC5627C56d;
