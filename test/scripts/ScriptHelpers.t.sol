// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { stdStorage, StdStorage, Test, stdError } from "forge-std/Test.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import "../../scripts/Constants.s.sol";
import "../../scripts/Utils.s.sol";

//solhint-disable
contract ScriptHelpers is Test, Utils {
    using stdStorage for StdStorage;

    uint256 constant valueEther = 1 ether;
    bytes[] private calldatasHelpers;
    string private descriptionHelpers;
    address[] private targetsHelpers;
    uint256[] private valuesHelpers;
    uint256[] private chainIdsHelpers;
    Vm.Log[] private entriesHelpers;
    bytes private payloadHelpers;

    function setUp() public virtual override {
        super.setUp();

        // TODO remove when on chain tx are passed to connect chains
        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);
        ProposalSender proposalSender = ProposalSender(
            payable(_chainToContract(CHAIN_SOURCE, ContractType.ProposalSender))
        );
        uint256[] memory ALL_CHAINS = new uint256[](10);
        ALL_CHAINS[0] = CHAIN_LINEA;
        ALL_CHAINS[1] = CHAIN_POLYGON;
        ALL_CHAINS[2] = CHAIN_ARBITRUM;
        ALL_CHAINS[3] = CHAIN_AVALANCHE;
        ALL_CHAINS[4] = CHAIN_OPTIMISM;
        ALL_CHAINS[5] = CHAIN_GNOSIS;
        ALL_CHAINS[6] = CHAIN_BNB;
        ALL_CHAINS[7] = CHAIN_CELO;
        ALL_CHAINS[8] = CHAIN_POLYGONZKEVM;
        ALL_CHAINS[9] = CHAIN_BASE;

        vm.startPrank(_chainToContract(CHAIN_SOURCE, ContractType.Governor));
        for (uint256 i; i < ALL_CHAINS.length; i++) {
            uint256 chainId = ALL_CHAINS[i];
            proposalSender.setTrustedRemoteAddress(
                _getLZChainId(chainId),
                abi.encodePacked(_chainToContract(chainId, ContractType.ProposalReceiver))
            );
        }
        vm.stopPrank();
    }

    function _executeProposalWithFork() public returns (uint256[] memory) {
        return _executeProposalInternal(true);
    }

    function _executeProposal() public returns (uint256[] memory) {
        return _executeProposalInternal(false);
    }

    function getProposalChainIds() public returns (uint256[] memory) {
        (, , , , uint256[] memory chainIds) = _deserializeJson();
        return chainIds;
    }

    function _executeProposalInternal(bool isFork) public returns (uint256[] memory) {
        (calldatasHelpers, descriptionHelpers, targetsHelpers, valuesHelpers, chainIdsHelpers) = _deserializeJson();

        vm.selectFork(forkIdentifier[isFork ? CHAIN_FORK : CHAIN_SOURCE]);
        {
            AngleGovernor governor = AngleGovernor(payable(_chainToContract(CHAIN_SOURCE, ContractType.Governor)));

            {
                hoax(whale);
                uint256 proposalId = governor.propose(
                    targetsHelpers,
                    valuesHelpers,
                    calldatasHelpers,
                    descriptionHelpers
                );
                vm.warp(block.timestamp + governor.votingDelay() + 1);
                vm.roll(block.number + governor.$votingDelayBlocks() + 1);

                hoax(whale);
                governor.castVote(proposalId, 1);
                vm.warp(block.timestamp + governor.votingPeriod() + 1);
            }

            vm.recordLogs();
            hoax(whale);
            governor.execute{ value: valueEther }(
                targetsHelpers,
                valuesHelpers,
                calldatasHelpers,
                keccak256(bytes(descriptionHelpers))
            );
        }
        entriesHelpers = vm.getRecordedLogs();

        for (uint256 chainCount; chainCount < chainIdsHelpers.length; chainCount++) {
            uint256 chainId = chainIdsHelpers[chainCount];
            TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
                payable(_chainToContract(chainId, ContractType.Timelock))
            );

            if (chainId == CHAIN_SOURCE) {
                vm.warp(block.timestamp + timelock.getMinDelay() + 1);
                _executeTimelock(chainId, timelock, targetsHelpers[chainCount], calldatasHelpers[chainCount]);
            } else {
                {
                    {
                        for (uint256 i; i < entriesHelpers.length; i++) {
                            if (
                                entriesHelpers[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)") &&
                                entriesHelpers[i].topics[1] == bytes32(uint256(_getLZChainId(chainId)))
                            ) {
                                payloadHelpers = abi.decode(entriesHelpers[i].data, (bytes));
                                break;
                            }
                        }
                    }

                    ProposalSender proposalSender = ProposalSender(
                        payable(_chainToContract(CHAIN_SOURCE, ContractType.ProposalSender))
                    );
                    ProposalReceiver proposalReceiver = ProposalReceiver(
                        payable(_chainToContract(chainId, ContractType.ProposalReceiver))
                    );

                    vm.selectFork(forkIdentifier[chainId]);
                    hoax(address(_lzEndPoint(chainId)));
                    proposalReceiver.lzReceive(
                        _getLZChainId(CHAIN_SOURCE),
                        abi.encodePacked(proposalSender, proposalReceiver),
                        0,
                        payloadHelpers
                    );
                }

                vm.warp(block.timestamp + timelock.getMinDelay() + 1);
                address[] memory chainTargets;
                bytes[] memory chainCalldatas;
                {
                    console.logBytes(calldatasHelpers[chainCount]);
                    (, bytes memory senderData, ) = abi.decode(
                        // calldatasHelpers[chainCount],
                        _slice(calldatasHelpers[chainCount], 4, calldatasHelpers[chainCount].length - 4),
                        (uint16, bytes, bytes)
                    );
                    console.logBytes(senderData);
                    (chainTargets, , , chainCalldatas) = abi.decode(
                        senderData,
                        (address[], uint256[], string[], bytes[])
                    );
                }

                for (uint256 i; i < chainTargets.length; i++) {
                    _executeTimelock(chainId, timelock, chainTargets[i], chainCalldatas[i]);
                }
            }
        }
        return chainIdsHelpers;
    }

    function _executeTimelock(
        uint256 chainId,
        TimelockControllerWithCounter timelock,
        address target,
        bytes memory rawData
    ) public returns (uint256[] memory) {
        // We only consider when transaction is sent to the chain timelock, as the other case shouldn't ask for another execute call
        if (target == address(timelock)) {
            vm.prank(_chainToContract(chainId, ContractType.GuardianMultisig));
            if (TimelockControllerWithCounter.schedule.selector == bytes4(_slice(rawData, 0, 4))) {
                (address target, uint256 value, bytes memory data, bytes32 predecessor, bytes32 salt, ) = abi.decode(
                    _slice(rawData, 4, rawData.length - 4),
                    (address, uint256, bytes, bytes32, bytes32, uint256)
                );
                timelock.execute(target, value, data, predecessor, salt);
            } else {
                (
                    address[] memory tmpTargets,
                    uint256[] memory tmpValues,
                    bytes[] memory tmpCalldatas,
                    bytes32 predecessor,
                    bytes32 salt,

                ) = abi.decode(
                        _slice(rawData, 4, rawData.length - 4),
                        (address[], uint256[], bytes[], bytes32, bytes32, uint256)
                    );
                timelock.executeBatch(tmpTargets, tmpValues, tmpCalldatas, predecessor, salt);
            }
        }
    }
}
