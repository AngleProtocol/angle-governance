// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";

import { console } from "forge-std/console.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

import { Proposal, SubCall } from "./Proposal.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "stringutils/strings.sol";

//solhint-disable
contract SimulationSetup is Test {
    using strings for *;

    Proposal proposal = new Proposal();

    uint256[] chainIds; // To list every needed chainId
    mapping(uint256 => string) mapChainIds;

    mapping(uint256 => uint256) forkIdentifier;
    mapping(uint256 => TimelockController) internal _timelocks;
    mapping(uint256 => ProposalReceiver) internal _proposalReceivers;
    ProposalSender internal _proposalSender;
    AngleGovernor public _governor;

    address public whale = 0xD13F8C25CceD32cdfA79EB5eD654Ce3e484dCAF5;
    IVotes public veANGLE = IVotes(0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5);

    function setUp() public {
        chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 137;

        mapChainIds[1] = "MAINNET";
        mapChainIds[137] = "POLYGON";
        // TODO Complete with all deployed chains

        vm.makePersistent(address(proposal));
        vm.makePersistent(address(veANGLE));
        string memory baseURI = "ETH_NODE_URI_";
        for (uint256 i; i < chainIds.length; i++) {
            forkIdentifier[chainIds[i]] = vm.createFork(
                vm.envString(baseURI.toSlice().concat(mapChainIds[chainIds[i]].toSlice()))
            );

            /// TODO Remove this part after deployment
            if (chainIds[i] == 1) {
                vm.selectFork(forkIdentifier[chainIds[i]]);
                address[] memory proposers = new address[](0);
                address[] memory executors = new address[](1);
                executors[0] = address(0); // Means everyone can execute

                _timelocks[chainIds[i]] = new TimelockController(1 days, proposers, executors, address(this));
                _governor = new AngleGovernor(veANGLE, _timelocks[chainIds[i]]);
                _timelocks[chainIds[i]].grantRole(_timelocks[chainIds[i]].PROPOSER_ROLE(), address(governor()));
                _timelocks[chainIds[i]].grantRole(_timelocks[chainIds[i]].CANCELLER_ROLE(), multisig(chainIds[i]));
                // _timelocks[chainIds[i]].renounceRole(_timelocks[chainIds[i]].TIMELOCK_ADMIN_ROLE(), address(this));
                _proposalSender = new ProposalSender(lzEndPoint(chainIds[i]));
            } else {
                vm.selectFork(forkIdentifier[chainIds[i]]);
                address[] memory proposers = new address[](0);
                address[] memory executors = new address[](1);
                executors[0] = address(0); // Means everyone can execute

                _timelocks[chainIds[i]] = new TimelockController(1 days, proposers, executors, address(this));
                _proposalReceivers[chainIds[i]] = new ProposalReceiver(address(lzEndPoint(chainIds[i])));
                _timelocks[chainIds[i]].grantRole(
                    _timelocks[chainIds[i]].PROPOSER_ROLE(),
                    address(_proposalReceivers[chainIds[i]])
                );
                _timelocks[chainIds[i]].grantRole(_timelocks[chainIds[i]].CANCELLER_ROLE(), multisig(chainIds[i]));

                vm.selectFork(forkIdentifier[1]);
                _proposalSender.setTrustedRemoteAddress(
                    getLZChainId(chainIds[i]),
                    abi.encodePacked(_proposalReceivers[chainIds[i]])
                );

                vm.selectFork(forkIdentifier[chainIds[i]]);
                _proposalReceivers[chainIds[i]].setTrustedRemoteAddress(
                    getLZChainId(1),
                    abi.encodePacked(_proposalSender)
                );
                _proposalReceivers[chainIds[i]].transferOwnership(address(_timelocks[chainIds[i]]));
            }
        }
        vm.selectFork(forkIdentifier[1]);
        _proposalSender.transferOwnership(address(_governor));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        VIRTUAL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// TODO Replace with functions fetching the address from the sdk
    function timelock(uint256 chainId) public view returns (TimelockController) {
        return _timelocks[chainId];
    }

    function proposalReceiver(uint256 chainId) public view returns (ProposalReceiver) {
        return _proposalReceivers[chainId];
    }

    function proposalSender() public view returns (ProposalSender) {
        return _proposalSender;
    }

    function governor() public view returns (AngleGovernor) {
        return _governor;
    }

    function multisig(uint256 chainId) public returns (address) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/multisig.js";
        cmd[2] = vm.toString(chainId);

        bytes memory res = vm.ffi(cmd);
        return address(bytes20(res));
    }

    function lzEndPoint(uint256 chainId) public returns (ILayerZeroEndpoint) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/layerZeroEndpoint.js";
        cmd[2] = vm.toString(chainId);

        bytes memory res = vm.ffi(cmd);
        return ILayerZeroEndpoint(address(bytes20(res)));
    }

    function stringToUint(string memory s) public pure returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }

    function getLZChainId(uint256 chainId) internal returns (uint16) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/layerZeroChainIds.js";
        cmd[2] = vm.toString(chainId);

        bytes memory res = vm.ffi(cmd);
        return uint16(stringToUint(string(res)));
    }

    function getChainId(uint256 lzChainId) internal returns (uint16) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/chainIdFromLZChainIds.js";
        cmd[2] = vm.toString(lzChainId);

        bytes memory res = vm.ffi(cmd);
        return uint16(stringToUint(string(res)));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Build the governor proposal based on all the transaction that need to be executed
    function wrap(
        SubCall[] memory prop
    ) internal returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) {
        targets = new address[](prop.length);
        values = new uint256[](prop.length);
        calldatas = new bytes[](prop.length);
        uint256 finalPropLength;
        uint256 i;
        while (i < prop.length) {
            uint256 chainId = prop[i].chainId;
            // Check the number of same chainId actions
            uint256 count = 1;
            while (i + count < prop.length && prop[i + count].chainId == chainId) {
                count++;
            }

            // Check that the chainId are consecutives
            for (uint256 j = i + count; j < prop.length; j++) {
                if (prop[j].chainId == chainId) {
                    revert("Invalid proposal, chainId must be gathered");
                }
            }

            if (chainId == 1) {
                vm.selectFork(forkIdentifier[1]);

                (
                    address[] memory batchTargets,
                    uint256[] memory batchValues,
                    bytes[] memory batchCalldatas
                ) = filterChainSubCalls(chainId, prop);
                (targets[finalPropLength], values[finalPropLength], calldatas[finalPropLength]) = wrapTimelock(
                    chainId,
                    prop
                );
                finalPropLength += 1;
                i += count;
            } else {
                vm.selectFork(forkIdentifier[chainId]);

                (
                    address[] memory batchTargets,
                    uint256[] memory batchValues,
                    bytes[] memory batchCalldatas
                ) = filterChainSubCalls(chainId, prop);
                (address target, uint256 value, bytes memory data) = wrapTimelock(chainId, prop);

                batchTargets = new address[](1);
                batchTargets[0] = target;
                batchValues = new uint256[](1);
                batchValues[0] = value;
                batchCalldatas = new bytes[](1);
                batchCalldatas[0] = data;

                // Wrap for proposal sender
                targets[finalPropLength] = address(proposalSender());
                values[finalPropLength] = 0.1 ether;
                calldatas[finalPropLength] = abi.encodeWithSelector(
                    proposalSender().execute.selector,
                    getLZChainId(chainId),
                    abi.encode(batchTargets, batchValues, new string[](1), batchCalldatas),
                    abi.encodePacked(uint16(1), uint256(300000))
                );
                finalPropLength += 1;
                i += count;
            }
        }
        assembly ("memory-safe") {
            mstore(targets, finalPropLength)
            mstore(values, finalPropLength)
            mstore(calldatas, finalPropLength)
        }
        vm.selectFork(forkIdentifier[1]); // Set back the fork to mainnet
    }

    function filterChainSubCalls(
        uint256 chainId,
        SubCall[] memory prop
    )
        internal
        pure
        returns (address[] memory batchTargets, uint256[] memory batchValues, bytes[] memory batchCalldatas)
    {
        uint256 count;
        batchTargets = new address[](prop.length);
        batchValues = new uint256[](prop.length);
        batchCalldatas = new bytes[](prop.length);
        for (uint256 j; j < prop.length; j++) {
            if (prop[j].chainId == chainId) {
                batchTargets[count] = prop[j].target;
                batchValues[count] = prop[j].value;
                batchCalldatas[count] = prop[j].data;
                count++;
            }
        }

        assembly ("memory-safe") {
            mstore(batchTargets, count)
            mstore(batchValues, count)
            mstore(batchCalldatas, count)
        }
    }

    function wrapTimelock(
        uint256 chainId,
        SubCall[] memory p
    ) public view returns (address target, uint256 value, bytes memory data) {
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        if (batchTargets.length == 1) {
            // In case the operation has already been done add a salt
            uint256 salt = computeSalt(chainId, p);
            // Simple schedule on timelock
            target = address(timelock(chainId));
            value = 0;
            data = abi.encodeWithSelector(
                timelock(chainId).schedule.selector,
                batchTargets[0],
                batchValues[0],
                batchCalldatas[0],
                bytes32(0),
                salt,
                timelock(chainId).getMinDelay()
            );
        } else {
            // In case the operation has already been done add a salt
            uint256 salt = computeSalt(chainId, p);
            target = address(timelock(chainId));
            value = 0;
            data = abi.encodeWithSelector(
                timelock(chainId).scheduleBatch.selector,
                batchTargets,
                batchValues,
                batchCalldatas,
                bytes32(0),
                salt,
                timelock(chainId).getMinDelay()
            );
        }
    }

    function executeTimelock(uint256 chainId, SubCall[] memory p) internal {
        vm.selectFork(forkIdentifier[chainId]);
        vm.warp(block.timestamp + timelock(chainId).getMinDelay() + 1);
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        uint256 salt = computeSalt(chainId, p);
        if (batchTargets.length == 1) {
            timelock(chainId).execute(batchTargets[0], batchValues[0], batchCalldatas[0], bytes32(0), 0);
        } else {
            timelock(chainId).executeBatch(batchTargets, batchValues, batchCalldatas, bytes32(0), 0);
        }
    }

    function computeSalt(uint256 chainId, SubCall[] memory p) internal view returns (uint256 salt) {
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        if (batchTargets.length == 1) {
            salt = 0;
            while (
                timelock(chainId).isOperation(
                    timelock(chainId).hashOperation(
                        batchTargets[0],
                        batchValues[0],
                        batchCalldatas[0],
                        bytes32(0),
                        bytes32(salt)
                    )
                )
            ) {
                salt++;
            }
        } else {
            salt = 0;
            while (
                timelock(chainId).isOperation(
                    timelock(chainId).hashOperationBatch(
                        batchTargets,
                        batchValues,
                        batchCalldatas,
                        bytes32(0),
                        bytes32(salt)
                    )
                )
            ) {
                salt++;
            }
        }
    }
}
