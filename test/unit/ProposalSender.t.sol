// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";
import { Strings } from "oz/utils/Strings.sol";

import { console } from "forge-std/console.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender, Ownable } from "contracts/ProposalSender.sol";

import { SubCall } from "./Proposal.sol";
import { SimulationSetup } from "./SimulationSetup.t.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "contracts/utils/Errors.sol" as Errors;
import "../Constants.t.sol";

//solhint-disable
contract ProposalSenderTest is SimulationSetup {
    event ExecuteRemoteProposal(uint16 indexed remoteChainId, bytes payload);

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function test_SetRelayerReceiver() public {
        vm.selectFork(forkIdentifier[10]);
        ProposalReceiver newReceiverOptimism = new ProposalReceiver(address(lzEndPoint(10)));
        newReceiverOptimism.setTrustedRemoteAddress(getLZChainId(1), abi.encodePacked(proposalSender()));
        newReceiverOptimism.transferOwnership(address(timelock(10)));

        {
            SubCall[] memory p = new SubCall[](2);
            p[0] = SubCall({
                chainId: 10,
                target: address(timelock(10)),
                value: 0,
                data: abi.encodeWithSelector(
                    timelock(10).grantRole.selector,
                    timelock(10).PROPOSER_ROLE(),
                    address(newReceiverOptimism)
                )
            });
            p[1] = SubCall({
                chainId: 10,
                target: address(timelock(10)),
                value: 0,
                data: abi.encodeWithSelector(
                    timelock(10).revokeRole.selector,
                    timelock(10).PROPOSER_ROLE(),
                    address(proposalReceiver(10))
                )
            });
            string memory description = "Updating relayer receiver on Optimism";
            _crossChainProposal(10, p, description, 0.1 ether, hex"", address(0));
        }

        vm.selectFork(forkIdentifier[1]);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(proposalSender());
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(
            proposalSender().setTrustedRemoteAddress.selector,
            getLZChainId(10),
            abi.encodePacked(address(newReceiverOptimism))
        );

        string memory description = "Updating trustedRemote relayer on Optimism";
        _shortcutProposal(1, description, targets, values, calldatas);

        vm.selectFork(forkIdentifier[1]);
        assertEq(
            proposalSender().trustedRemoteLookup(getLZChainId(10)),
            abi.encodePacked(address(proposalReceiver(10)), address(proposalSender()))
        );
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(
            proposalSender().trustedRemoteLookup(getLZChainId(10)),
            abi.encodePacked(address(newReceiverOptimism), address(proposalSender()))
        );

        // now passing a tx on Optimism should go through the new receiver
        _proposalReceivers[10] = newReceiverOptimism;
        {
            SubCall[] memory p = new SubCall[](1);
            p[0] = SubCall({
                chainId: 10,
                target: address(timelock(10)),
                value: 0,
                data: abi.encodeWithSelector(timelock(10).updateDelay.selector, 100)
            });
            description = "Updating delay on Optimism";
            vm.selectFork(forkIdentifier[10]);
            assertEq(timelock(10).getMinDelay() != 100, true);

            _crossChainProposal(10, p, description, 0.1 ether, hex"", address(0));
            vm.selectFork(forkIdentifier[10]);
            assertEq(timelock(10).getMinDelay() == 100, true);
        }
    }

    function test_SetRelayerSenderConfig() public {
        vm.selectFork(forkIdentifier[1]);

        uint64 defaultBlockConfirmation = 0;

        /** Can be modified  */
        uint16 version = 2;
        uint16 chainId = 1;
        uint16 configType = 2;
        uint64 blockConfirmation = 365;
        /** Stop  */

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(proposalSender());
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(
            proposalSender().setConfig.selector,
            version,
            chainId,
            configType,
            abi.encode(blockConfirmation)
        );
        string memory description = "Updating config on Mainnet";

        assertEq(proposalSender().getConfig(version, chainId, configType), abi.encode(defaultBlockConfirmation));
        _shortcutProposal(1, description, targets, values, calldatas);
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(proposalSender().getConfig(version, chainId, configType), abi.encode(blockConfirmation));
    }

    function test_SetRelayerSenderSendVersion() public {
        vm.selectFork(forkIdentifier[1]);

        uint64 defaultVersion = 2;

        /** Can be modified  */
        uint16 version = 1;
        /** Stop  */

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(proposalSender());
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(proposalSender().setSendVersion.selector, version);
        string memory description = "Updating sendVersion on Mainnet";

        _shortcutProposal(1, description, targets, values, calldatas);
        assertEq(lzEndPoint(1).getSendVersion(address(proposalSender())), defaultVersion);
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(lzEndPoint(1).getSendVersion(address(proposalSender())), 1);
    }

    function test_RevertWhen_lzEndpointFail() public {
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(timelock(137).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 1);
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        (uint nativeFee, uint zroFee) = proposalSender().estimateFees(getLZChainId(137), payload, adapterParams);
        assertEq(zroFee, 0);
        assertGt(nativeFee, 0);
        assertLe(nativeFee, 0.1 ether);
        bytes memory execution = abi.encode(getLZChainId(137), payload, adapterParams, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), keccak256(execution));
    }

    function test_RevertWhen_NoFailTx() public {
        uint64 nonce = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.OmnichainProposalSenderNoStoredPayload.selector));
        proposalSender().retryExecute(nonce, getLZChainId(137), hex"", hex"", 1);
    }

    function test_RevertWhen_RetryExecuteWrongParams() public {
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(timelock(137).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        vm.expectRevert(abi.encodeWithSelector(Errors.OmnichainProposalSenderInvalidExecParams.selector));
        proposalSender().retryExecute(1, getLZChainId(137), hex"", hex"", 1);
    }

    function test_RetryExecuteSimple() public {
        uint256 destChain = 137;

        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        vm.mockCallRevert(
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        (uint256 nativeFee, ) = proposalSender().estimateFees(getLZChainId(137), payload, adapterParams);
        assertLe(nativeFee, 0.1 ether);
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        vm.clearMockedCalls();
        // We need to execute with an address to get the eth refund
        vm.startPrank(alice);
        proposalSender().retryExecute(1, getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );

        vm.selectFork(forkIdentifier[destChain]);
        vm.warp(block.timestamp + timelock(destChain).getMinDelay() + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        assertEq(timelock(destChain).getMinDelay() != 100, true);
        timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(timelock(destChain).getMinDelay() == 100, true);
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
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
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
        proposalSender().retryExecute(1, getLZChainId(destChain), payload1, adapterParams1, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.prank(alice);
        proposalSender().retryExecute(2, getLZChainId(destChain), payload2, adapterParams2, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(2), bytes32(0));

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload1
        );

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

        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload2
        );
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

    function test_RetryExecuteMulti_OrderRetryInverseReceive() public {
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
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
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
        proposalSender().retryExecute(1, getLZChainId(destChain), payload1, adapterParams1, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.prank(alice);
        proposalSender().retryExecute(2, getLZChainId(destChain), payload2, adapterParams2, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(2), bytes32(0));

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload2
        );

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

        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload1
        );
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

    function test_RetryExecuteMulti_InverseRetryOrderReceive() public {
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
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
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
        proposalSender().retryExecute(2, getLZChainId(destChain), payload2, adapterParams2, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(2), bytes32(0));

        vm.prank(alice);
        proposalSender().retryExecute(1, getLZChainId(destChain), payload1, adapterParams1, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload1
        );

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

        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload2
        );
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
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
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
        proposalSender().retryExecute(2, getLZChainId(destChain), payload2, adapterParams2, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(2), bytes32(0));

        vm.prank(alice);
        proposalSender().retryExecute(1, getLZChainId(destChain), payload1, adapterParams1, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload2
        );

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

        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload1
        );
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
            address(lzEndPoint(1)),
            abi.encodeWithSelector(lzEndPoint(1).send.selector),
            abi.encode("REVERT")
        );
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002c48f2a0bb000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000151800000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000442f2ff15db09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc10000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        vm.clearMockedCalls();
        // We need to execute with an address to get the eth refund
        vm.startPrank(alice);
        proposalSender().retryExecute(1, getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        assertEq(proposalSender().storedExecutionHashes(1), bytes32(0));

        vm.selectFork(forkIdentifier[destChain]);
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );

        vm.selectFork(forkIdentifier[destChain]);
        vm.warp(block.timestamp + timelock(destChain).getMinDelay() + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        assertEq(timelock(destChain).getMinDelay() != 100, true);
        timelock(destChain).executeBatch(targets, values, calldatas, bytes32(0), 0);
        assertEq(timelock(destChain).getMinDelay() == 100, true);
    }

    function test_MainnetChangeAngleGovernorAndTimelock() public {
        vm.selectFork(forkIdentifier[1]);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute
        TimelockController timelock2 = new TimelockController(1 days, proposers, executors, address(this));
        AngleGovernor governor2 = new AngleGovernor(
            veANGLEDelegation,
            address(timelock2),
            initialVotingDelay,
            initialVotingPeriod,
            initialProposalThreshold,
            initialVoteExtension,
            initialQuorumNumerator,
            initialShortCircuitNumerator,
            initialVotingDelayBlocks
        );
        timelock2.grantRole(timelock2.PROPOSER_ROLE(), address(governor2));
        timelock2.grantRole(timelock2.CANCELLER_ROLE(), multisig(chainIds[1]));

        vm.label(address(timelock2), "New timelock");
        vm.label(address(governor2), "New governor");

        // In a real setup you would need to set also the owner of all angle contracts to the new timelock

        // either the long road
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: 1,
            target: address(governor()),
            value: 0,
            // not direct way to call this function, but just to use the utils functions
            data: abi.encodeWithSelector(
                governor().relay.selector,
                proposalSender(),
                0,
                abi.encodeWithSelector(proposalSender().transferOwnership.selector, address(governor2))
            )
        });
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        // or the short one with no timelock
        targets[0] = address(proposalSender());
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(proposalSender().transferOwnership.selector, address(governor2));

        string memory description = "Updating Angle Governor";
        _shortcutProposal(1, description, targets, values, calldatas);
        assertEq(_proposalSender.owner(), address(governor()));
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(_proposalSender.owner(), address(governor2));

        // reset back to the old governor
        calldatas[0] = abi.encodeWithSelector(proposalSender().transferOwnership.selector, address(governor()));
        // Then let's try to pass a proposal with the old timelock/governor
        _shortcutProposal(1, description, targets, values, calldatas);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, governor()));
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));

        // Set in current contract storage the governor and timelock
        AngleGovernor realGovernor = governor();
        TimelockController realTimelock = timelock(1);
        _governor = governor2;
        _timelocks[1] = timelock2;

        // Pass a proposal with the new timelock/governor
        _shortcutProposal(1, description, targets, values, calldatas);
        governor().execute(targets, values, calldatas, keccak256(bytes(description)));

        // reset the storage for other test
        _governor = realGovernor;
        _timelocks[1] = realTimelock;

        assertEq(_proposalSender.owner(), address(governor()));
        assertEq(_proposalSender.owner(), address(realGovernor));
    }

    function test_PolygonUpdateProposalReceiver() public {
        vm.selectFork(forkIdentifier[137]);
        ProposalReceiver proposalReceiver2 = new ProposalReceiver(address(lzEndPoint(137)));
        proposalReceiver2.setTrustedRemoteAddress(getLZChainId(1), abi.encodePacked(_proposalSender));
        proposalReceiver2.transferOwnership(address(timelock(137)));
        address newProposalReceiver = address(proposalReceiver2);

        vm.selectFork(forkIdentifier[1]);

        SubCall[] memory p = new SubCall[](3);
        p[0] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(1).grantRole.selector,
                timelock(1).PROPOSER_ROLE(),
                newProposalReceiver
            )
        });
        p[1] = SubCall({
            chainId: 137,
            target: address(timelock(137)),
            value: 0,
            data: abi.encodeWithSelector(
                timelock(1).revokeRole.selector,
                timelock(1).PROPOSER_ROLE(),
                address(proposalReceiver(137))
            )
        });
        p[2] = SubCall({
            chainId: 1,
            target: address(proposalSender()),
            value: 0,
            data: abi.encodeWithSelector(
                proposalSender().setTrustedRemoteAddress.selector,
                getLZChainId(137),
                abi.encodePacked(proposalReceiver2)
            )
        });

        string memory description = "Updating Proposal receiver on Polygon";

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = wrap(p);

        hoax(whale);
        uint256 proposalId = governor().propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor().votingDelay() + 1);
        vm.roll(block.number + governor().$votingDelayBlocks() + 1);

        hoax(whale);
        governor().castVote(proposalId, 1);
        vm.warp(block.timestamp + governor().votingPeriod() + 1);

        vm.recordLogs();
        governor().execute{ value: 0.1 ether }(targets, values, calldatas, keccak256(bytes(description))); // TODO Optimize value

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory payload;
        for (uint256 i; i < entries.length; i++) {
            if (
                entries[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)") &&
                entries[i].topics[1] == bytes32(uint256(getLZChainId(137)))
            ) {
                payload = abi.decode(entries[i].data, (bytes));
                break;
            }
        }

        vm.selectFork(forkIdentifier[137]);
        hoax(address(lzEndPoint(137)));
        proposalReceiver(137).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(137)),
            0,
            payload
        );

        // Final test
        vm.warp(block.timestamp + timelock(137).getMinDelay() + 1);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver(137))), true);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver2)), false);
        (targets, values, calldatas) = filterChainSubCalls(137, p);
        timelock(137).executeBatch(targets, values, calldatas, bytes32(0), 0);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver(137))), false);
        assertEq(timelock(137).hasRole(_timelocks[137].PROPOSER_ROLE(), address(proposalReceiver2)), true);
    }

    function test_RevertWhen_ReceiverCallFail() public {
        uint256 destChain = 137;
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100)
        });
        string memory description = "Updating delay on Optimism";
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);

        vm.selectFork(forkIdentifier[destChain]);
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        bytes memory execution = abi.encode(getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        vm.mockCallRevert(
            address(timelock(destChain)),
            abi.encodeWithSelector(timelock(destChain).schedule.selector),
            abi.encode(TimelockController.TimelockUnexpectedOperationState.selector, hex"", hex"01")
        );
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );
        assertEq(
            proposalReceiver(destChain).failedMessages(
                getLZChainId(1),
                abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
                0
            ),
            keccak256(payload)
        );

        vm.expectRevert(Errors.OmnichainGovernanceExecutorTxExecReverted.selector);
        proposalReceiver(destChain).retryMessage(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );
        vm.clearMockedCalls();

        assertEq(timelock(destChain).getMinDelay() != 100, true);
        proposalReceiver(destChain).retryMessage(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            0,
            payload
        );

        vm.warp(block.timestamp + timelock(destChain).getMinDelay() + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(timelock(destChain).getMinDelay() == 100, true);
    }

    function test_RevertWhen_Receiver2ndCallFail() public {
        uint256 destChain = 137;

        vm.selectFork(forkIdentifier[destChain]);
        uint256 oldDelay = timelock(destChain).getMinDelay();

        vm.selectFork(forkIdentifier[1]);
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 1371)
        });
        string memory description = "Updating delay on Optimism";
        _crossChainProposal(destChain, p, description, 0.1 ether, hex"", address(0));
        assertEq(timelock(destChain).getMinDelay() == 1371, true);

        p[0].data = abi.encodeWithSelector(timelock(destChain).updateDelay.selector, 100);
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);

        vm.selectFork(forkIdentifier[destChain]);
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        bytes memory execution = abi.encode(getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        vm.mockCallRevert(
            address(timelock(destChain)),
            abi.encodeWithSelector(timelock(destChain).schedule.selector),
            abi.encode(TimelockController.TimelockUnexpectedOperationState.selector, hex"", hex"01")
        );
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            1,
            payload
        );
        assertEq(
            proposalReceiver(destChain).failedMessages(
                getLZChainId(1),
                abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
                1
            ),
            keccak256(payload)
        );

        vm.expectRevert(Errors.OmnichainGovernanceExecutorTxExecReverted.selector);
        proposalReceiver(destChain).retryMessage(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            1,
            payload
        );
        vm.clearMockedCalls();

        assertEq(timelock(destChain).getMinDelay() != 100, true);
        proposalReceiver(destChain).retryMessage(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            1,
            payload
        );

        vm.warp(block.timestamp + oldDelay + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(timelock(destChain).getMinDelay() == 100, true);
    }

    function test_RevertWhen_Receiver2ndCallTooSmallDelay() public {
        uint256 destChain = 137;

        vm.selectFork(forkIdentifier[destChain]);
        uint256 oldDelay = timelock(destChain).getMinDelay();
        uint256 newDelay = 1371;
        newDelay = bound(newDelay, 1, oldDelay);

        vm.selectFork(forkIdentifier[1]);
        SubCall[] memory p = new SubCall[](1);
        p[0] = SubCall({
            chainId: destChain,
            target: address(timelock(destChain)),
            value: 0,
            data: abi.encodeWithSelector(timelock(destChain).updateDelay.selector, newDelay)
        });
        string memory description = "Updating delay on Optimism";
        _crossChainProposal(destChain, p, description, 0.1 ether, hex"", address(0));
        assertEq(timelock(destChain).getMinDelay() == newDelay, true);

        p[0].data = abi.encodeWithSelector(timelock(destChain).updateDelay.selector, oldDelay);
        vm.selectFork(forkIdentifier[1]);
        // Making the call revert to force replay
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);
        _dummyProposal(1, p, description, 0.1 ether, hex"");
        assertEq(uint256(proposalSender().lastStoredPayloadNonce()), 0);

        vm.selectFork(forkIdentifier[destChain]);
        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0cb889707d426a7a386870a03bc70d1b06975980000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000012401d5062a000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015180000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        bytes memory execution = abi.encode(getLZChainId(destChain), payload, adapterParams, 0.1 ether);
        vm.mockCallRevert(
            address(timelock(destChain)),
            abi.encodeWithSelector(timelock(destChain).schedule.selector),
            abi.encode(TimelockController.TimelockUnexpectedOperationState.selector, hex"", hex"01")
        );
        hoax(address(lzEndPoint(destChain)));
        proposalReceiver(destChain).lzReceive(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            1,
            payload
        );
        vm.clearMockedCalls();

        assertEq(timelock(destChain).getMinDelay() != oldDelay, true);
        proposalReceiver(destChain).retryMessage(
            getLZChainId(1),
            abi.encodePacked(proposalSender(), proposalReceiver(destChain)),
            1,
            payload
        );

        vm.warp(block.timestamp + newDelay + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = filterChainSubCalls(
            destChain,
            p
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                keccak256(
                    abi.encode(
                        address(timelock(destChain)),
                        0,
                        abi.encodeWithSelector(timelock(destChain).updateDelay.selector, oldDelay),
                        bytes32(0),
                        bytes32(0)
                    )
                ),
                bytes32(1 << uint8(TimelockController.OperationState.Ready))
            )
        );
        timelock(destChain).execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
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
}
