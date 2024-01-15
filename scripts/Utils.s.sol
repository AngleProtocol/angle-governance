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
contract Utils is Script, HelpersAddress, HelpersJson {
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

    function setUp() public virtual {
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

    function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        // Check length is 0. `iszero` return 1 for `true` and 0 for `false`.
        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // Calculate length mod 32 to handle slices that are not a multiple of 32 in size.
                let lengthmod := and(_length, 31)

                // tempBytes will have the following format in memory: <length><data>
                // When copying data we will offset the start forward to avoid allocating additional memory
                // Therefore part of the length area will be written, but this will be overwritten later anyways.
                // In case no offset is require, the start is set to the data region (0x20 from the tempBytes)
                // mc will be used to keep track where to copy the data to.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // Same logic as for mc is applied and additionally the start offset specified for the method is added
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    // increase `mc` and `cc` to read the next word from memory
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // Copy the data from source (cc location) to the slice data (mc location)
                    mstore(mc, mload(cc))
                }

                // Store the length of the slice. This will overwrite any partial data that
                // was copied when having slices that are not a multiple of 32.
                mstore(tempBytes, _length)

                // update free-memory pointer
                // allocating the array padded to 32 bytes like the compiler does now
                // To set the used memory as a multiple of 32, add 31 to the actual memory usage (mc)
                // and remove the modulo 32 (the `and` with `not(31)`)
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            // if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                // zero out the 32 bytes slice we are about to return
                // we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                // update free-memory pointer
                // tempBytes uses 32 bytes in memory (even when empty) for the length.
                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
}
