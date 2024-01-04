// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "../Utils.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract ProposalSenderRetry is Utils {
    function run() external {
        // TODO can be modified to deploy on any chain
        uint256 destChainId = CHAIN_POLYGON;
        // END

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        ProposalSender sender = proposalSender();

        bytes
            memory payload = hex"000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000010000000000000000000000001305d45d583378d38fa614bbd9b45d6a0704690d000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002c48f2a0bb000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012c00000000000000000000000000000000000000000000000000000000000000020000000000000000000000001305d45d583378d38fa614bbd9b45d6a0704690d0000000000000000000000001305d45d583378d38fa614bbd9b45d6a0704690d0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002464d6235300000000000000000000000000000000000000000000000000000000000000fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000442f2ff15dd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63000000000000000000000000fda462548ce04282f4b6d6619823a7c64fdc01850000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(300000));
        sender.retryExecute{ value: 1 ether }(1, getLZChainId(destChainId), payload, adapterParams, 0.01 ether);
    }
}
