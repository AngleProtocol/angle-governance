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

    function _executeProposal() public returns (uint256[] memory) {
        (
            bytes[] memory calldatas,
            string memory description,
            address[] memory targets,
            uint256[] memory values,
            uint256[] memory chainIds
        ) = _deserializeJson();

        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);
        AngleGovernor governor = AngleGovernor(payable(_chainToContract(CHAIN_SOURCE, ContractType.Governor)));
        ProposalSender proposalSender = ProposalSender(
            payable(_chainToContract(CHAIN_SOURCE, ContractType.ProposalSender))
        );

        {
            hoax(whale);
            uint256 proposalId = governor.propose(targets, values, calldatas, description);
            vm.warp(block.timestamp + governor.votingDelay() + 1);
            vm.roll(block.number + governor.$votingDelayBlocks() + 1);

            hoax(whale);
            governor.castVote(proposalId, 1);
            vm.warp(block.timestamp + governor.votingPeriod() + 1);
        }

        vm.recordLogs();
        hoax(whale);
        governor.execute{ value: valueEther }(targets, values, calldatas, keccak256(bytes(description)));

        for (uint256 chainCount; chainCount < chainIds.length; chainCount++) {
            uint256 chainId = chainIds[chainCount];
            TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
                payable(_chainToContract(chainId, ContractType.Timelock))
            );

            if (chainId == CHAIN_SOURCE) {} else {
                ProposalReceiver proposalReceiver = ProposalReceiver(
                    payable(_chainToContract(chainId, ContractType.ProposalReceiver))
                );

                {
                    bytes memory payload;
                    {
                        Vm.Log[] memory entries = vm.getRecordedLogs();
                        for (uint256 i; i < entries.length; i++) {
                            if (
                                entries[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)") &&
                                entries[i].topics[1] == bytes32(uint256(getLZChainId(chainId)))
                            ) {
                                payload = abi.decode(entries[i].data, (bytes));
                                break;
                            }
                        }
                    }

                    vm.selectFork(forkIdentifier[chainId]);
                    hoax(address(lzEndPoint(chainId)));
                    proposalReceiver.lzReceive(
                        getLZChainId(CHAIN_SOURCE),
                        abi.encodePacked(proposalSender, proposalReceiver),
                        0,
                        payload
                    );
                }

                vm.warp(block.timestamp + timelock.getMinDelay() + 1);
                // (targets, values, calldatas) = filterChainSubCalls(chainId, p);
                (address[] memory chainTargets, , , bytes[] memory chainCalldatas) = abi.decode(
                    calldatas[chainCount],
                    (address[], uint256[], string[], bytes[])
                );
                for (uint256 i; i < chainTargets.length; i++) {
                    // We only consider when transaction is sent to the chain timelock, as the other case shouldn't ask for another execute call
                    if (chainTargets[i] == address(timelock)) {
                        if (TimelockControllerWithCounter.schedule.selector == bytes4(slice(chainCalldatas[i], 0, 4))) {
                            (
                                address target,
                                uint256 value,
                                bytes memory data,
                                bytes32 predecessor,
                                bytes32 salt,

                            ) = abi.decode(
                                    slice(chainCalldatas[i], 4, chainCalldatas[i].length - 4),
                                    (address, uint256, bytes, bytes32, bytes32, uint256)
                                );
                            timelock.execute(target, value, data, predecessor, salt);
                            // id = timelock.hashOperation(target, value, data, predecessor, salt);
                        } else {
                            (
                                address[] memory tmpTargets,
                                uint256[] memory tmpValues,
                                bytes[] memory tmpCalldatas,
                                bytes32 predecessor,
                                bytes32 salt,

                            ) = abi.decode(
                                    slice(chainCalldatas[i], 4, chainCalldatas[i].length - 4),
                                    (address[], uint256[], bytes[], bytes32, bytes32, uint256)
                                );
                            timelock.executeBatch(tmpTargets, tmpValues, tmpCalldatas, predecessor, salt);
                            // id = timelock.hashOperationBatch(targets, values, calldatas, predecessor, salt);
                        }
                    }
                }
            }
        }
        return chainIds;
    }
}
