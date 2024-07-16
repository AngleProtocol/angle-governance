// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz-v5/governance/IGovernor.sol";
import { IVotes } from "oz-v5/governance/extensions/GovernorVotes.sol";
import { IAccessControl } from "oz-v5/access/IAccessControl.sol";
import { Strings } from "oz-v5/utils/Strings.sol";

import { console } from "forge-std/console.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender, Ownable } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter, TimelockController } from "contracts/TimelockControllerWithCounter.sol";

import { SubCall } from "./Proposal.sol";
import { SimulationSetup } from "./SimulationSetup.t.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "contracts/utils/Errors.sol" as Errors;
import "../Constants.t.sol";

// TODO check that only proposer can schedule a tx

//solhint-disable
contract TimelockControllerWithCounterTest is SimulationSetup {
    event ExecuteRemoteProposal(uint16 indexed remoteChainId, bytes payload);

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function test_MainnetSimpleVote() public {
        uint256 srcChain = 1;
        vm.selectFork(forkIdentifier[srcChain]);

        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 1,
            target: address(governor()),
            value: 0,
            data: abi.encodeWithSelector(governor().updateQuorumNumerator.selector, 11)
        });
        string memory description = "Updating Quorum";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor().votingDelay() + 1);
        vm.roll(block.number + governor().$votingDelayBlocks() + 1);

        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.warp(block.timestamp + governor().votingPeriod() + 1);

        governor().state(proposalId);

        vm.selectFork(forkIdentifier[srcChain]);
        assertEq(timelock(srcChain).counterProposals(), 0);
        assertEq(timelock(srcChain).proposalIds(0), 0);
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        bytes32 txId = timelock(srcChain).hashOperation(
            address(governor()),
            0,
            abi.encodeWithSelector(governor().updateQuorumNumerator.selector, 11),
            bytes32(0),
            0
        );
        assertEq(timelock(srcChain).counterProposals(), 1);
        assertEq(timelock(srcChain).proposalIds(0), txId);

        vm.warp(block.timestamp + timelock(srcChain).getMinDelay() + 1);
        assertEq(governor().quorumNumerator(), 10);
        (targets, values, calldatas) = filterChainSubCalls(srcChain, p);
        timelock(srcChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);

        assertEq(governor().quorumNumerator(), 11);
    }

    function test_SetRelayerReceiver() public {
        uint256 srcChain = 1;
        uint256 destChain = 10;
        vm.selectFork(forkIdentifier[destChain]);
        ProposalReceiver newReceiverOptimism = new ProposalReceiver(address(_lzEndPoint(destChain)));
        newReceiverOptimism.setTrustedRemoteAddress(_getLZChainId(srcChain), abi.encodePacked(proposalSender()));
        newReceiverOptimism.transferOwnership(address(timelock(destChain)));

        {
            SubCall[] memory p = new SubCall[](2);
            p[0] = SubCall({
                chainId: destChain,
                target: address(timelock(destChain)),
                value: 0,
                data: abi.encodeWithSelector(
                    timelock(destChain).grantRole.selector,
                    timelock(destChain).PROPOSER_ROLE(),
                    address(newReceiverOptimism)
                )
            });
            p[1] = SubCall({
                chainId: destChain,
                target: address(timelock(destChain)),
                value: 0,
                data: abi.encodeWithSelector(
                    timelock(destChain).revokeRole.selector,
                    timelock(destChain).PROPOSER_ROLE(),
                    address(proposalReceiver(destChain))
                )
            });
            string memory description = "Updating relayer receiver on Optimism";
            vm.selectFork(forkIdentifier[srcChain]);
            assertEq(timelock(srcChain).counterProposals(), 0);
            assertEq(timelock(srcChain).proposalIds(0), 0);
            vm.selectFork(forkIdentifier[destChain]);
            assertEq(timelock(destChain).counterProposals(), 0);
            assertEq(timelock(destChain).proposalIds(0), 0);
            bytes32 txId = _crossChainProposal(destChain, p, description, 0.1 ether, hex"", address(0));
            assertEq(timelock(destChain).counterProposals(), 1);
            assertEq(timelock(destChain).proposalIds(0), txId);
            vm.selectFork(forkIdentifier[srcChain]);
            assertEq(timelock(srcChain).counterProposals(), 0);
            assertEq(timelock(srcChain).proposalIds(0), 0);
        }

        vm.selectFork(forkIdentifier[srcChain]);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(proposalSender());
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(
            proposalSender().setTrustedRemoteAddress.selector,
            _getLZChainId(destChain),
            abi.encodePacked(address(newReceiverOptimism))
        );

        string memory description = "Updating trustedRemote relayer on Optimism";
        _shortcutProposal(srcChain, description, targets, values, calldatas);

        vm.selectFork(forkIdentifier[srcChain]);
        assertEq(
            proposalSender().trustedRemoteLookup(_getLZChainId(destChain)),
            abi.encodePacked(address(proposalReceiver(destChain)), address(proposalSender()))
        );
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(
            proposalSender().trustedRemoteLookup(_getLZChainId(destChain)),
            abi.encodePacked(address(newReceiverOptimism), address(proposalSender()))
        );

        // now passing a tx on Optimism should go through the new receiver
        _proposalReceivers[destChain] = newReceiverOptimism;
        {
            SubCall[] memory p = new SubCall[](1);
            p[0] = SubCall({
                chainId: destChain,
                target: address(timelock(destChain)),
                value: 0,
                data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
            });
            description = "Updating delay on Optimism";
            assertEq(timelock(srcChain).counterProposals(), 0);
            assertEq(timelock(srcChain).proposalIds(0), 0);

            vm.selectFork(forkIdentifier[destChain]);
            assertEq(timelock(destChain).getMinDelay() != 100, true);
            assertEq(timelock(destChain).counterProposals(), 1);
            assertNotEq(timelock(destChain).proposalIds(0), bytes32(0));
            bytes32 txId = _crossChainProposal(destChain, p, description, 0.1 ether, hex"", address(0));
            vm.selectFork(forkIdentifier[srcChain]);
            assertEq(timelock(srcChain).counterProposals(), 0);
            assertEq(timelock(srcChain).proposalIds(0), 0);
            vm.selectFork(forkIdentifier[destChain]);
            assertEq(timelock(destChain).counterProposals(), 2);
            assertEq(timelock(destChain).proposalIds(1), txId);
            assertEq(timelock(destChain).getMinDelay() == 100, true);
        }
    }

    function test_RetryExecuteSimple() public {
        uint256 destChain = 137;
        uint256 srcChain = 1;

        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[srcChain]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(_lzEndPoint(srcChain)),
            abi.encodeWithSelector(_lzEndPoint(srcChain).send.selector),
            abi.encode("REVERT")
        );
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        (uint256 nativeFee, ) = proposalSender().estimateFees(_getLZChainId(destChain), payload, adapterParams);
        assertLe(nativeFee, 0.1 ether);
        _dummyProposal(srcChain, p, description, 0.1 ether, hex"");
        vm.clearMockedCalls();
        // We need to execute with an address to get the eth refund
        vm.startPrank(alice);
        proposalSender().retryExecute(1, _getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));
        vm.stopPrank();

        assertEq(timelock(srcChain).counterProposals(), 0);
        assertEq(timelock(srcChain).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 0);
        assertEq(timelock(destChain).proposalIds(0), 0);

        hoax(address(_lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            _getLZChainId(srcChain),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );

        vm.selectFork(forkIdentifier[srcChain]);
        assertEq(timelock(srcChain).counterProposals(), 0);
        assertEq(timelock(srcChain).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 1);
        assertGe(timelock(destChain).getTimestamp(timelock(destChain).proposalIds(0)), block.timestamp);

        vm.warp(block.timestamp + timelock(destChain).getMinDelay() + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        assertEq(timelock(destChain).getMinDelay() != 100, true);
        timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(timelock(destChain).counterProposals(), 1);
        assertEq(
            timelock(destChain).proposalIds(0),
            timelock(destChain).hashOperation(targets[0], values[0], calldatas[0], bytes32(0), 0)
        );
        assertEq(timelock(destChain).getMinDelay() == 100, true);
        vm.selectFork(forkIdentifier[srcChain]);
        assertEq(timelock(srcChain).counterProposals(), 0);
        assertEq(timelock(srcChain).proposalIds(0), 0);
    }

    function test_RetryExecuteMulti_OrderRetryOrderReceive() public {
        uint256 destChain = 137;

        SubCall[] memory p1 = new SubCall[](1);
        p1[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(_lzEndPoint(1)),
            abi.encodeWithSelector(_lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        bytes
            memory payload1 = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams1 = abi.encodePacked(uint16(1), uint256(300000));
        _dummyProposal(1, p1, description, 0.1 ether, hex"");

        SubCall[] memory p2 = new SubCall[](1);
        p2[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(destChain).grantRole.selector,
                timelock(1).PROPOSER_ROLE(),
                address(alice)
            )
        });
        description = "Grant role on Optimism";
        bytes
            memory payload2 = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000014401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001518000000000000000000000000000000000000000000000000000000000000000442f2ff15db09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc10000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams2 = abi.encodePacked(uint16(1), uint256(300000));
        _dummyProposal(1, p2, description, 0.1 ether, hex"");

        vm.clearMockedCalls();
        // We need to execute with an address to get the eth refund
        vm.prank(alice);
        proposalSender().retryExecute(1, _getLZChainId(destChain), payload1, adapterParams1, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.prank(alice);
        proposalSender().retryExecute(2, _getLZChainId(destChain), payload2, adapterParams2, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(2), bytes32(0));

        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 0);
        assertEq(timelock(destChain).proposalIds(0), 0);

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(_lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            _getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload1
        );

        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 1);
        assertEq(timelock(destChain).proposalIds(0), _decodeLzReceivePayload(payload1, destChain, false));

        uint256 oldDelay = timelock(destChain).getMinDelay();
        vm.selectFork(forkIdentifier[destChain]);
        vm.warp(block.timestamp + oldDelay + 1);
        {
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
                destChain,
                p1
            );
            assertEq(timelock(destChain).getMinDelay() != 100, true);
            timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
            assertEq(timelock(destChain).getMinDelay() == 100, true);
        }

        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 1);

        hoax(address(_lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            _getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload2
        );

        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 2);
        assertEq(timelock(destChain).proposalIds(1), _decodeLzReceivePayload(payload2, destChain, false));

        vm.warp(block.timestamp + oldDelay + 1);

        {
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
                destChain,
                p2
            );
            assertEq(timelock(destChain).hasRole(timelock(destChain).PROPOSER_ROLE(), alice), false);
            timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
            assertEq(timelock(destChain).hasRole(timelock(destChain).PROPOSER_ROLE(), alice), true);
        }
    }

    function test_RetryExecuteMulti_InverseRetryInverseReceive() public {
        uint256 destChain = 137;

        SubCall[] memory p1 = new SubCall[](1);
        p1[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(_lzEndPoint(1)),
            abi.encodeWithSelector(_lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        bytes
            memory payload1 = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams1 = abi.encodePacked(uint16(1), uint256(300000));
        _dummyProposal(1, p1, description, 0.1 ether, hex"");

        SubCall[] memory p2 = new SubCall[](1);
        p2[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(destChain).grantRole.selector,
                timelock(1).PROPOSER_ROLE(),
                address(alice)
            )
        });
        description = "Grant role on Optimism";
        bytes
            memory payload2 = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000014401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001518000000000000000000000000000000000000000000000000000000000000000442f2ff15db09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc10000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams2 = abi.encodePacked(uint16(1), uint256(300000));
        _dummyProposal(1, p2, description, 0.1 ether, hex"");

        vm.clearMockedCalls();
        // We need to execute with an address to get the eth refund
        vm.prank(alice);
        proposalSender().retryExecute(2, _getLZChainId(destChain), payload2, adapterParams2, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(2), bytes32(0));

        vm.prank(alice);
        proposalSender().retryExecute(1, _getLZChainId(destChain), payload1, adapterParams1, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 0);
        assertEq(timelock(destChain).proposalIds(0), 0);

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(_lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            _getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload2
        );

        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 1);
        assertEq(timelock(destChain).proposalIds(0), _decodeLzReceivePayload(payload2, destChain, false));

        uint256 oldDelay = timelock(destChain).getMinDelay();
        vm.selectFork(forkIdentifier[destChain]);
        vm.warp(block.timestamp + oldDelay + 1);
        {
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
                destChain,
                p2
            );
            assertEq(timelock(destChain).hasRole(timelock(destChain).PROPOSER_ROLE(), alice), false);
            timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
            assertEq(timelock(destChain).hasRole(timelock(destChain).PROPOSER_ROLE(), alice), true);
        }

        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 1);

        hoax(address(_lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            _getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload1
        );
        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 2);
        assertEq(timelock(destChain).proposalIds(1), _decodeLzReceivePayload(payload1, destChain, false));

        vm.warp(block.timestamp + oldDelay + 1);

        {
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
                destChain,
                p1
            );
            assertEq(timelock(destChain).getMinDelay() != 100, true);
            timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
            assertEq(timelock(destChain).getMinDelay() == 100, true);
        }
    }

    function test_RetryExecuteBatch() public {
        uint256 destChain = 137;

        SubCall[] memory p = new SubCall[](2);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        p[1] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(destChain).grantRole.selector,
                timelock(1).PROPOSER_ROLE(),
                address(alice)
            )
        });
        string memory description = "Batch delay and grantRole on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(_lzEndPoint(1)),
            abi.encodeWithSelector(_lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002c48f2a0bb000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000151800000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000442f2ff15db09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc10000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        vm.clearMockedCalls();
        // We need to execute with an address to get the eth refund
        vm.startPrank(alice);
        proposalSender().retryExecute(1, _getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));
        vm.stopPrank();

        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 0);
        assertEq(timelock(destChain).proposalIds(0), 0);

        hoax(address(_lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            _getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );

        vm.selectFork(forkIdentifier[1]);
        assertEq(timelock(1).counterProposals(), 0);
        assertEq(timelock(1).proposalIds(0), 0);
        vm.selectFork(forkIdentifier[destChain]);
        assertEq(timelock(destChain).counterProposals(), 1);
        assertEq(timelock(destChain).proposalIds(0), _decodeLzReceivePayload(payload, destChain, true));

        vm.warp(block.timestamp + timelock(destChain).getMinDelay() + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        assertEq(timelock(destChain).getMinDelay() != 100, true);
        timelock(destChain).executeBatch(targets, values, calldatas, bytes32(0), 0);
        assertEq(timelock(destChain).getMinDelay() == 100, true);
    }

    function test_RevertWhen_NotProposerScheduleSingle() public {
        uint256 srcChain = 1;
        vm.selectFork(forkIdentifier[srcChain]);

        uint256 minDelay = timelock(srcChain).getMinDelay();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                timelock(srcChain).PROPOSER_ROLE()
            )
        );
        vm.prank(alice);
        timelock(srcChain).schedule(
            address(timelock(srcChain)),
            0,
            abi.encodeWithSelector(timelock(srcChain).updateDelay.selector, 100),
            bytes32(0),
            0,
            minDelay
        );
    }

    function test_RevertWhen_NotProposerScheduleBatch() public {
        uint256 srcChain = 1;
        vm.selectFork(forkIdentifier[srcChain]);

        address[] memory targets = new address[](1);
        targets[0] = address(timelock(srcChain));
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(timelock(srcChain).updateDelay.selector, 100);

        uint256 minDelay = timelock(srcChain).getMinDelay();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                timelock(srcChain).PROPOSER_ROLE()
            )
        );
        vm.prank(alice);
        timelock(srcChain).scheduleBatch(targets, values, payloads, bytes32(0), 0, minDelay);
    }

    function test_RevertWhen_TimelockSidechainNotExecutor() public {
        uint256 destChain = 137;

        vm.selectFork(forkIdentifier[destChain]);
        timelock(destChain).grantRole(timelock(destChain).EXECUTOR_ROLE(), multisig(destChain));
        timelock(destChain).revokeRole(timelock(destChain).EXECUTOR_ROLE(), address(0));

        vm.selectFork(forkIdentifier[1]);
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";

        bytes memory error = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            alice,
            timelock(1).EXECUTOR_ROLE()
        );
        _crossChainProposal(destChain, p, description, 0.1 ether, error, alice);
    }

    function test_TimelockSidechainExecutor() public {
        uint256 destChain = 137;

        vm.selectFork(forkIdentifier[destChain]);
        timelock(destChain).grantRole(timelock(destChain).EXECUTOR_ROLE(), multisig(destChain));
        timelock(destChain).revokeRole(timelock(destChain).EXECUTOR_ROLE(), address(0));

        vm.selectFork(forkIdentifier[1]);
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        _crossChainProposal(destChain, p, description, 0.1 ether, hex"", multisig(destChain));
        assertEq(timelock(destChain).getMinDelay() == 100, true);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _decodeLzReceivePayload(
        bytes memory payload,
        uint256 chainId,
        bool isBatch
    ) internal view returns (bytes32) {
        (, , , bytes[] memory calldatas) = abi.decode(payload, (address[], uint256[], string[], bytes[]));
        bytes memory higherData = calldatas[0];
        if (isBatch) return this._decodePayloadTimelockScheduleBatch(higherData, chainId);
        else return this._decodePayloadTimelockSchedule(higherData, chainId);
    }

    function _decodePayloadTimelockSchedule(bytes calldata payload, uint256 chainId) public view returns (bytes32 id) {
        (address target, uint256 value, bytes memory data, bytes32 predecessor, bytes32 salt, ) = abi.decode(
            payload[4:],
            (address, uint256, bytes, bytes32, bytes32, uint256)
        );
        return timelock(chainId).hashOperation(target, value, data, predecessor, salt);
    }

    function _decodePayloadTimelockScheduleBatch(
        bytes calldata payload,
        uint256 chainId
    ) public view returns (bytes32 id) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory datas,
            bytes32 predecessor,
            bytes32 salt,

        ) = abi.decode(payload[4:], (address[], uint256[], bytes[], bytes32, bytes32, uint256));
        return timelock(chainId).hashOperationBatch(targets, values, datas, predecessor, salt);
    }
}
