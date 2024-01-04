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

    function timelock(uint256 chainId) public returns (TimelockControllerWithCounter) {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "utils/contractAddress.js";
        cmd[2] = vm.toString(chainId);
        cmd[3] = "timelock";

        bytes memory res = vm.ffi(cmd);
        if (res.length == 0) revert("Chain not supported");
        return TimelockControllerWithCounter(payable(address(bytes20(res))));
    }

    function proposalReceiver(uint256 chainId) public returns (ProposalReceiver) {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "utils/contractAddress.js";
        cmd[2] = vm.toString(chainId);
        cmd[3] = "proposalReceiver";

        bytes memory res = vm.ffi(cmd);
        if (res.length == 0) revert("Chain not supported");
        return ProposalReceiver(payable(address(bytes20(res))));
    }

    /// TODO Replace with prod chain
    function proposalSender() public returns (ProposalSender) {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "utils/contractAddress.js";
        cmd[2] = vm.toString(CHAIN_GNOSIS);
        cmd[3] = "proposalSender";

        bytes memory res = vm.ffi(cmd);
        if (res.length == 0) revert("Chain not supported");
        return ProposalSender(payable(address(bytes20(res))));
    }

    /// TODO Replace with prod chain
    function governor() public returns (AngleGovernor) {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "utils/contractAddress.js";
        cmd[2] = vm.toString(CHAIN_GNOSIS);
        cmd[3] = "governor";

        bytes memory res = vm.ffi(cmd);
        if (res.length == 0) revert("Chain not supported");
        return AngleGovernor(payable(address(bytes20(res))));
    }

    function lzEndPoint(uint256 chainId) public returns (ILayerZeroEndpoint) {
        // TODO temporary check if LZ updated their sdk
        if (chainId == CHAIN_GNOSIS) {
            return ILayerZeroEndpoint(0x9740FF91F1985D8d2B71494aE1A2f723bb3Ed9E4);
        }

        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/layerZeroEndpoint.js";
        cmd[2] = vm.toString(chainId);

        bytes memory res = vm.ffi(cmd);
        if (res.length == 0) revert("Chain not supported");
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
        if (res.length == 0) revert("Chain not supported");
        return uint16(stringToUint(string(res)));
    }
}
