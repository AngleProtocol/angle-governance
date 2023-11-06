// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

import { Proposal, SubCall } from "./Proposal.sol";
import { SimulationSetup } from "./SimulationSetup.t.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "stringutils/strings.sol";

//solhint-disable
contract Simulate is SimulationSetup {
    function test_Simulate() public {
        (SubCall[] memory p, string memory description) = proposal.proposal();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        vm.selectFork(forkIdentifier[1]);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.roll(block.number + governor().votingDelay() + 1);
        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.roll(block.number + governor().votingPeriod() + 1);

        vm.recordLogs();
        governor().execute{ value: 1 ether }(targets, values, calldatas, keccak256(bytes(description)));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Mainnet execution
        (address[] memory batchTargets, , ) = filterChainSubCalls(1, p);
        if (batchTargets.length > 0) {
            executeTimelock(1, p);
        }

        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)")) {
                bytes memory payload = abi.decode(entries[i].data, (bytes));
                uint16 chainId = getChainId(uint16(uint256((entries[i].topics[1]))));
                vm.selectFork(forkIdentifier[chainId]);
                hoax(address(lzEndPoint(chainId)));
                proposalReceiver(chainId).lzReceive(
                    getLZChainId(1),
                    abi.encodePacked(proposalSender(), proposalReceiver(chainId)),
                    0,
                    payload
                );

                // Final test
                executeTimelock(chainId, p);
            }
        }

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INSERT TESTS HERE                                                
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    }
}
