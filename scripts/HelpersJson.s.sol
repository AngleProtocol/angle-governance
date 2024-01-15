// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./Constants.s.sol";

/// @title HelpersJson
/// @author Angle Labs, Inc.
contract HelpersJson is Script {
    // function _deserializeJson()
    //     internal
    //     returns (bytes[] memory, string memory, address[] memory, uint256[] memory, uint256[] memory)
    // {
    //     string memory root = vm.projectRoot();
    //     string memory path = string.concat(root, pathProposal);
    //     string memory json = vm.readFile(path);
    //     bytes memory encodedStruct = vm.parseJson(json, ".description");
    //     description = abi.decode(encodedStruct, (string));
    //     {
    //         string memory calldataKey = ".calldatas";
    //         string[] memory keys = vm.parseJsonKeys(json, calldataKey);
    //         // Iterate over the encoded structs
    //         for (uint256 i = 0; i < keys.length; ++i) {
    //             string memory structKey = string.concat(calldataKey, ".", keys[i]);
    //             bytes memory encodedStruct = vm.parseJson(json, structKey);
    //             calldatas.push(abi.decode(encodedStruct, (bytes)));
    //         }
    //     }
    //     {
    //         string memory targetsKey = ".targets";
    //         string[] memory keys = vm.parseJsonKeys(json, targetsKey);
    //         // Iterate over the encoded structs
    //         for (uint256 i = 0; i < keys.length; ++i) {
    //             string memory structKey = string.concat(targetsKey, ".", keys[i]);
    //             bytes memory encodedStruct = vm.parseJson(json, structKey);
    //             targets.push(abi.decode(encodedStruct, (address)));
    //         }
    //     }
    //     {
    //         string memory valuesKey = ".values";
    //         string[] memory keys = vm.parseJsonKeys(json, valuesKey);
    //         // Iterate over the encoded structs
    //         for (uint256 i = 0; i < keys.length; ++i) {
    //             string memory structKey = string.concat(valuesKey, ".", keys[i]);
    //             bytes memory encodedStruct = vm.parseJson(json, structKey);
    //             values.push(abi.decode(encodedStruct, (uint256)));
    //         }
    //     }
    //     {
    //         string memory chainIdsKey = ".chainIds";
    //         string[] memory keys = vm.parseJsonKeys(json, chainIdsKey);
    //         // Iterate over the encoded structs
    //         for (uint256 i = 0; i < keys.length; ++i) {
    //             string memory structKey = string.concat(chainIdsKey, ".", keys[i]);
    //             bytes memory encodedStruct = vm.parseJson(json, structKey);
    //             chainIds.push(abi.decode(encodedStruct, (uint256)));
    //         }
    //     }
    //     return (calldatas, description, targets, values, chainIds);
    // }
    // function _serializeJson(
    //     address[] memory targets,
    //     uint256[] memory values,
    //     bytes[] memory calldatas,
    //     uint256[] memory chainIds,
    //     string memory description
    // ) internal {
    //     string memory json = "chain";
    //     {
    //         string memory jsonTargets = "targets";
    //         string memory targetsOutput;
    //         for (uint256 i; i < targets.length; i++) {
    //             targetsOutput = vm.serializeAddress(jsonTargets, vm.toString(i), targets[i]);
    //         }
    //         vm.serializeString(json, "targets", targetsOutput);
    //     }
    //     {
    //         string memory jsonValues = "values";
    //         string memory valuesOutput;
    //         for (uint256 i; i < values.length; i++) {
    //             valuesOutput = vm.serializeUint(jsonValues, vm.toString(i), values[i]);
    //         }
    //         vm.serializeString(json, "values", valuesOutput);
    //     }
    //     {
    //         string memory jsonCalldatas = "calldatas";
    //         string memory calldatasOutput;
    //         for (uint256 i; i < calldatas.length; i++) {
    //             calldatasOutput = vm.serializeBytes(jsonCalldatas, vm.toString(i), calldatas[i]);
    //         }
    //         vm.serializeString(json, "calldatas", calldatasOutput);
    //     }
    //     {
    //         string memory jsonChainIds = "chainIds";
    //         string memory chainIdsOutput;
    //         for (uint256 i; i < chainIds.length; i++) {
    //             chainIdsOutput = vm.serializeUint(jsonChainIds, vm.toString(i), chainIds[i]);
    //         }
    //         vm.serializeString(json, "chainIds", chainIdsOutput);
    //     }
    //     string memory output = vm.serializeString(json, "description", description);
    //     string memory root = vm.projectRoot();
    //     string memory path = string.concat(root, pathProposal);
    //     vm.writeJson(output, path);
    // }
}
