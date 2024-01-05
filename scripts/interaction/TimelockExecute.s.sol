// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "../Utils.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract TimelockExecute is Utils {
    function run() external {
        // TODO can be modified to deploy on any chain
        uint256 chainId = CHAIN_POLYGON;
        // END

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), "m/44'/60'/0'/0/", 2);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        TimelockControllerWithCounter timelockDestChain = TimelockControllerWithCounter(payable(timelock(chainId)));

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = address(timelockDestChain);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(timelockDestChain.updateDelay.selector, 200);

        targets[1] = address(timelockDestChain);
        values[1] = 0;
        calldatas[1] = abi.encodeWithSelector(
            timelockDestChain.grantRole.selector,
            0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63, //timelockDestChain.EXECUTOR_ROLE(),
            address(0)
        );

        timelockDestChain.executeBatch(targets, values, calldatas, bytes32(0), bytes32(0));
    }
}
