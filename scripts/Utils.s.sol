// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "oz/proxy/transparent/ProxyAdmin.sol";
import "oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "./Constants.s.sol";

import { console } from "forge-std/console.sol";

contract Utils is Script {
    //Update this address based on needs
    address public constant PROXY_ADMIN = 0x1D941EF0D3Bba4ad67DBfBCeE5262F4CEE53A32b;

    function deployUpgradeable(address implementation, bytes memory data) public returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, PROXY_ADMIN, data));
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
}
