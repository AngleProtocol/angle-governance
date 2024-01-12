// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import { ITreasury } from "borrow/interfaces/ITreasury.sol";
import "./Constants.s.sol";

/// @title Utils
/// @author Angle Labs, Inc.
contract Utils is Script {
    mapping(uint256 => uint256) internal forkIdentifier;
    uint256 public arbitrumFork;
    uint256 public avalancheFork;
    uint256 public ethereumFork;
    uint256 public optimismFork;
    uint256 public gnosisFork;
    uint256 public polygonFork;

    bytes[] private calldatas;
    string private description;
    address[] private targets;
    uint256[] private values;
    uint256[] private chainIds;

    function setUp() public {
        arbitrumFork = vm.createFork(vm.envString("ETH_NODE_URI_ARBITRUM"));
        avalancheFork = vm.createFork(vm.envString("ETH_NODE_URI_AVALANCHE"));
        ethereumFork = vm.createFork(vm.envString("ETH_NODE_URI_MAINNET"));
        optimismFork = vm.createFork(vm.envString("ETH_NODE_URI_OPTIMISM"));
        gnosisFork = vm.createFork(vm.envString("ETH_NODE_URI_GNOSIS"));
        polygonFork = vm.createFork(vm.envString("ETH_NODE_URI_POLYGON"));

        forkIdentifier[CHAIN_ARBITRUM] = arbitrumFork;
        forkIdentifier[CHAIN_AVALANCHE] = avalancheFork;
        forkIdentifier[CHAIN_ETHEREUM] = ethereumFork;
        forkIdentifier[CHAIN_OPTIMISM] = optimismFork;
        forkIdentifier[CHAIN_GNOSIS] = gnosisFork;
        forkIdentifier[CHAIN_POLYGON] = polygonFork;
    }

    function lzEndPoint(uint256 chainId) public returns (ILayerZeroEndpoint) {
        // TODO temporary check if LZ updated their sdk
        if (chainId == CHAIN_GNOSIS) {
            return ILayerZeroEndpoint(0x9740FF91F1985D8d2B71494aE1A2f723bb3Ed9E4);
        } else if (chainId == CHAIN_ZKEVMPOLYGON) {
            return ILayerZeroEndpoint(0x9740FF91F1985D8d2B71494aE1A2f723bb3Ed9E4);
        } else if (chainId == CHAIN_BASE) {
            return ILayerZeroEndpoint(0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7);
        } else if (chainId == CHAIN_CELO) {
            return ILayerZeroEndpoint(0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9);
        } else if (chainId == CHAIN_LINEA) {
            return ILayerZeroEndpoint(0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7);
        }

        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/layerZeroEndpoint.js";
        cmd[2] = vm.toString(chainId);

        bytes memory res = vm.ffi(cmd);
        if (res.length == 0) revert("Chain not supported");
        return ILayerZeroEndpoint(address(bytes20(res)));
    }

    function _chainToContract(uint256 chainId, ContractType name) internal returns (address) {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "utils/contractAddress.js";
        cmd[2] = vm.toString(chainId);

        if (name == ContractType.Timelock) cmd[3] = "timelock";
        else if (name == ContractType.ProposalReceiver) cmd[3] = "proposalReceiver";
        else if (name == ContractType.ProposalSender) cmd[3] = "proposalSender";
        else if (name == ContractType.Governor) cmd[3] = "governor";
        else if (name == ContractType.GuardianMultisig) cmd[3] = "guardian";
        else if (name == ContractType.TreasuryAgEUR) cmd[3] = "treasury";
        else if (name == ContractType.StEUR) cmd[3] = "stEUR";
        else if (name == ContractType.TransmuterAgEUR) cmd[3] = "transmuterAgEUR";
        else if (name == ContractType.CoreBorrow) cmd[3] = "coreBorrow";
        else if (name == ContractType.GovernorMultisig) cmd[3] = "governorMultisig";
        else if (name == ContractType.ProxyAdmin) cmd[3] = "proxyAdmin";
        else if (name == ContractType.Angle) cmd[3] = "angle";
        else if (name == ContractType.veANGLE) cmd[3] = "veANGLE";
        else if (name == ContractType.SmartWalletWhitelist) cmd[3] = "smartWalletWhitelist";
        else if (name == ContractType.veBoostProxy) cmd[3] = "veBoostProxy";
        else if (name == ContractType.GaugeController) cmd[3] = "gaugeController";
        else if (name == ContractType.AngleDistributor) cmd[3] = "angleDistributor";
        else if (name == ContractType.AngleMiddleman) cmd[3] = "angleMiddleman";
        else if (name == ContractType.FeeDistributor) cmd[3] = "feeDistributor";
        else revert("contract not supported");

        bytes memory res = vm.ffi(cmd);
        // When process exit code is 1, it will return an empty bytes "0x"
        if (res.length == 0) revert("Chain not supported");
        return address(bytes20(res));
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
        if (res.length == 0) revert("Chain not supported");
        return uint16(stringToUint(string(res)));
    }

    function _chainToContract(uint256 chainId, ContractType name) internal returns (address) {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "utils/contractAddress.js";
        cmd[2] = vm.toString(chainId);

        if (name == ContractType.Timelock) cmd[3] = "timelock";
        else if (name == ContractType.ProposalReceiver) cmd[3] = "proposalReceiver";
        else if (name == ContractType.ProposalSender) cmd[3] = "proposalSender";
        else if (name == ContractType.Governor) cmd[3] = "governor";
        else if (name == ContractType.TreasuryAgEUR) cmd[3] = "treasury";
        else if (name == ContractType.StEUR) cmd[3] = "stEUR";
        else if (name == ContractType.TransmuterAgEUR) cmd[3] = "transmuterAgEUR";
        else if (name == ContractType.CoreBorrow) cmd[3] = "coreBorrow";
        else if (name == ContractType.GovernorMultisig) cmd[3] = "governorMultisig";
        else if (name == ContractType.ProxyAdmin) cmd[3] = "proxyAdmin";
        else if (name == ContractType.Angle) cmd[3] = "angle";
        else if (name == ContractType.veANGLE) cmd[3] = "veANGLE";
        else if (name == ContractType.SmartWalletWhitelist) cmd[3] = "smartWalletWhitelist";
        else if (name == ContractType.veBoostProxy) cmd[3] = "veBoostProxy";
        else if (name == ContractType.GaugeController) cmd[3] = "gaugeController";
        else if (name == ContractType.AngleDistributor) cmd[3] = "angleDistributor";
        else if (name == ContractType.AngleMiddleman) cmd[3] = "angleMiddleman";
        else if (name == ContractType.FeeDistributor) cmd[3] = "feeDistributor";
        else revert("contract not supported");

        bytes memory res = vm.ffi(cmd);
        // When process exit code is 1, it will return an empty bytes "0x"
        if (res.length == 0) revert("Chain not supported");
        return address(bytes20(res));
    }

    function wrapTimelock(
        uint256 chainId,
        SubCall[] memory p
    ) public returns (address target, uint256 value, bytes memory data) {
        TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
            payable(_chainToContract(chainId, ContractType.Timelock))
        );
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        if (batchTargets.length == 1) {
            // In case the operation has already been done add a salt
            uint256 salt = computeSalt(chainId, p);
            // Simple schedule on timelock
            target = address(timelock);
            value = 0;
            data = abi.encodeWithSelector(
                timelock.schedule.selector,
                batchTargets[0],
                batchValues[0],
                batchCalldatas[0],
                bytes32(0),
                salt,
                timelock.getMinDelay()
            );
        } else {
            // In case the operation has already been done add a salt
            uint256 salt = computeSalt(chainId, p);
            target = address(timelock);
            value = 0;
            data = abi.encodeWithSelector(
                timelock.scheduleBatch.selector,
                batchTargets,
                batchValues,
                batchCalldatas,
                bytes32(0),
                salt,
                timelock.getMinDelay()
            );
        }
    }

    function computeSalt(uint256 chainId, SubCall[] memory p) internal returns (uint256 salt) {
        TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
            payable(_chainToContract(chainId, ContractType.Timelock))
        );
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        if (batchTargets.length == 1) {
            salt = 0;
            while (
                timelock.isOperation(
                    timelock.hashOperation(
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
                timelock.isOperation(
                    timelock.hashOperationBatch(batchTargets, batchValues, batchCalldatas, bytes32(0), bytes32(salt))
                )
            ) {
                salt++;
            }
        }
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

    function _wrap(
        SubCall[] memory prop
    )
        internal
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, uint256[] memory chainIds)
    {
        targets = new address[](prop.length);
        values = new uint256[](prop.length);
        calldatas = new bytes[](prop.length);
        chainIds = new uint256[](prop.length);

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
                (targets[finalPropLength], values[finalPropLength], calldatas[finalPropLength]) = wrapTimelock(
                    chainId,
                    prop
                );
                chainIds[finalPropLength] = chainId;
                finalPropLength += 1;
                i += count;
            } else {
                vm.selectFork(forkIdentifier[chainId]);
                (address target, uint256 value, bytes memory data) = wrapTimelock(chainId, prop);

                address[] memory batchTargets = new address[](1);
                batchTargets[0] = target;
                uint256[] memory batchValues = new uint256[](1);
                batchValues[0] = value;
                bytes[] memory batchCalldatas = new bytes[](1);
                batchCalldatas[0] = data;

                // Wrap for proposal sender
                ProposalSender proposalSender = ProposalSender(_chainToContract(chainId, ContractType.ProposalSender));
                targets[finalPropLength] = address(proposalSender);
                values[finalPropLength] = 0.1 ether;
                chainIds[finalPropLength] = chainId;
                calldatas[finalPropLength] = abi.encodeWithSelector(
                    proposalSender.execute.selector,
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
    }

    function _deserializeJson()
        internal
        returns (bytes[] memory, string memory, address[] memory, uint256[] memory, uint256[] memory)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/proposals.json");
        string memory json = vm.readFile(path);

        bytes memory encodedStruct = vm.parseJson(json, ".description");
        description = abi.decode(encodedStruct, (string));
        {
            string memory calldataKey = ".calldatas";
            string[] memory keys = vm.parseJsonKeys(json, calldataKey);
            // Iterate over the encoded structs
            for (uint256 i = 0; i < keys.length; ++i) {
                string memory structKey = string.concat(calldataKey, ".", keys[i]);
                bytes memory encodedStruct = vm.parseJson(json, structKey);
                calldatas.push(abi.decode(encodedStruct, (bytes)));
            }
        }
        {
            string memory targetsKey = ".targets";
            string[] memory keys = vm.parseJsonKeys(json, targetsKey);
            // Iterate over the encoded structs
            for (uint256 i = 0; i < keys.length; ++i) {
                string memory structKey = string.concat(targetsKey, ".", keys[i]);
                bytes memory encodedStruct = vm.parseJson(json, structKey);
                targets.push(abi.decode(encodedStruct, (address)));
            }
        }
        {
            string memory valuesKey = ".values";
            string[] memory keys = vm.parseJsonKeys(json, valuesKey);
            // Iterate over the encoded structs
            for (uint256 i = 0; i < keys.length; ++i) {
                string memory structKey = string.concat(valuesKey, ".", keys[i]);
                bytes memory encodedStruct = vm.parseJson(json, structKey);
                values.push(abi.decode(encodedStruct, (uint256)));
            }
        }
        {
            string memory chainIdsKey = ".chainIds";
            string[] memory keys = vm.parseJsonKeys(json, chainIdsKey);
            // Iterate over the encoded structs
            for (uint256 i = 0; i < keys.length; ++i) {
                string memory structKey = string.concat(chainIdsKey, ".", keys[i]);
                bytes memory encodedStruct = vm.parseJson(json, structKey);
                chainIds.push(abi.decode(encodedStruct, (uint256)));
            }
        }
        return (calldatas, description, targets, values, chainIds);
    }

    function _serializeJson(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        uint256[] memory chainIds,
        string memory description
    ) internal {
        string memory json = "chain";

        {
            string memory jsonTargets = "targets";
            string memory targetsOutput;
            for (uint256 i; i < targets.length; i++) {
                targetsOutput = vm.serializeAddress(jsonTargets, vm.toString(i), targets[i]);
            }
            vm.serializeString(json, "targets", targetsOutput);
        }
        {
            string memory jsonValues = "values";
            string memory valuesOutput;
            for (uint256 i; i < values.length; i++) {
                valuesOutput = vm.serializeUint(jsonValues, vm.toString(i), values[i]);
            }
            vm.serializeString(json, "values", valuesOutput);
        }
        {
            string memory jsonCalldatas = "calldatas";
            string memory calldatasOutput;
            for (uint256 i; i < calldatas.length; i++) {
                calldatasOutput = vm.serializeBytes(jsonCalldatas, vm.toString(i), calldatas[i]);
            }
            vm.serializeString(json, "calldatas", calldatasOutput);
        }
        {
            string memory jsonChainIds = "chainIds";
            string memory chainIdsOutput;
            for (uint256 i; i < chainIds.length; i++) {
                chainIdsOutput = vm.serializeUint(jsonChainIds, vm.toString(i), chainIds[i]);
            }
            vm.serializeString(json, "chainIds", chainIdsOutput);
        }
        string memory output = vm.serializeString(json, "description", description);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/proposals.json");
        vm.writeJson(output, path);
    }
}
