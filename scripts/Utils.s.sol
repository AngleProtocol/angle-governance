// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import { ITreasury } from "borrow/interfaces/ITreasury.sol";
import "utils/src/CommonUtils.sol";
import "./Constants.s.sol";

/// @title Utils
/// @author Angle Labs, Inc.
contract Utils is Script, CommonUtils {
    mapping(uint256 => uint256) internal forkIdentifier;
    uint256 public arbitrumFork;
    uint256 public avalancheFork;
    uint256 public ethereumFork;
    uint256 public optimismFork;
    uint256 public polygonFork;
    uint256 public gnosisFork;
    uint256 public bnbFork;
    uint256 public celoFork;
    uint256 public polygonZkEVMFork;
    uint256 public baseFork;
    uint256 public lineaFork;

    bytes[] private calldatas;
    string private description;
    address[] private targets;
    uint256[] private values;
    uint256[] private chainIds;

    function setUp() public virtual {
        arbitrumFork = vm.createFork(vm.envString("ETH_NODE_URI_ARBITRUM"));
        avalancheFork = vm.createFork(vm.envString("ETH_NODE_URI_AVALANCHE"));
        ethereumFork = vm.createFork(vm.envString("ETH_NODE_URI_MAINNET"));
        optimismFork = vm.createFork(vm.envString("ETH_NODE_URI_OPTIMISM"));
        polygonFork = vm.createFork(vm.envString("ETH_NODE_URI_POLYGON"));
        gnosisFork = vm.createFork(vm.envString("ETH_NODE_URI_GNOSIS"));
        bnbFork = vm.createFork(vm.envString("ETH_NODE_URI_BSC"));
        celoFork = vm.createFork(vm.envString("ETH_NODE_URI_CELO"));
        polygonZkEVMFork = vm.createFork(vm.envString("ETH_NODE_URI_POLYGON_ZKEVM"));
        baseFork = vm.createFork(vm.envString("ETH_NODE_URI_BASE"));
        lineaFork = vm.createFork(vm.envString("ETH_NODE_URI_LINEA"));

        forkIdentifier[CHAIN_ARBITRUM] = arbitrumFork;
        forkIdentifier[CHAIN_AVALANCHE] = avalancheFork;
        forkIdentifier[CHAIN_ETHEREUM] = ethereumFork;
        forkIdentifier[CHAIN_OPTIMISM] = optimismFork;
        forkIdentifier[CHAIN_POLYGON] = polygonFork;
        forkIdentifier[CHAIN_GNOSIS] = gnosisFork;
        forkIdentifier[CHAIN_BNB] = bnbFork;
        forkIdentifier[CHAIN_CELO] = celoFork;
        forkIdentifier[CHAIN_POLYGONZKEVM] = polygonZkEVMFork;
        forkIdentifier[CHAIN_BASE] = baseFork;
        forkIdentifier[CHAIN_LINEA] = lineaFork;
    }

    function _deserializeJson()
        internal
        returns (bytes[] memory, string memory, address[] memory, uint256[] memory, uint256[] memory)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, pathProposal);
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
        string memory path = string.concat(root, pathProposal);
        vm.writeJson(output, path);
    }
}
