// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";

contract ProposalSenderConnectTest is ScriptHelpers {
    using stdJson for string;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        (
            bytes[] memory calldatas,
            string memory description,
            address[] memory targets,
            uint256[] memory values,
            uint256[] memory chainIds
        ) = _deserializeJson();

        AngleGovernor governor = AngleGovernor(payable(_chainToContract(CHAIN_SOURCE, ContractType.Governor)));
        ProposalSender sender = ProposalSender(payable(_chainToContract(CHAIN_SOURCE, ContractType.ProposalSender)));

        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);

        vm.startPrank(whale);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.roll(block.number + governor.$votingDelayBlocks() + 1);

        governor.castVote(proposalId, 1);
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        governor.execute{ value: valueEther }(targets, values, calldatas, keccak256(bytes(description)));
        vm.stopPrank();

        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];

            address receiver = _chainToContract(chainId, ContractType.ProposalReceiver);
            bytes memory trustedRemote = sender.trustedRemoteLookup(getLZChainId(chainId));
            address connectedReceiver = address(bytes20(slice(trustedRemote, 0, 20)));
            assertEq(receiver, connectedReceiver);
        }
    }
}
