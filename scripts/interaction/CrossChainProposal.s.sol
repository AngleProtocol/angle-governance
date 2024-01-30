// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "../Utils.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract CrossChainProposal is Utils {
    function run() external {
        // TODO can be modified to deploy on any chain
        uint256 srcChainId = CHAIN_ETHEREUM;
        uint256 destChainId = CHAIN_POLYGON;
        // END

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        AngleGovernor governor = AngleGovernor(payable(_chainToContract(destChainId, ContractType.Governor)));
        ProposalSender sender = ProposalSender(payable(_chainToContract(srcChainId, ContractType.ProposalSender)));
        TimelockControllerWithCounter timelockDestChain = TimelockControllerWithCounter(
            payable(_chainToContract(destChainId, ContractType.Timelock))
        );

        address[] memory timelockTargets = new address[](1);
        uint256[] memory timelockValues = new uint256[](1);
        bytes[] memory timelockCalldatas = new bytes[](1);

        {
            address[] memory batchTargets = new address[](2);
            uint256[] memory batchValues = new uint256[](2);
            bytes[] memory batchCalldatas = new bytes[](2);

            batchTargets[0] = address(timelockDestChain);
            batchValues[0] = 0;
            batchCalldatas[0] = abi.encodeWithSelector(timelockDestChain.updateDelay.selector, 200);

            batchTargets[1] = address(timelockDestChain);
            batchValues[1] = 0;
            batchCalldatas[1] = abi.encodeWithSelector(
                timelockDestChain.grantRole.selector,
                0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63, //timelockDestChain.EXECUTOR_ROLE(),
                address(0)
            );

            timelockTargets[0] = address(timelockDestChain);
            timelockValues[0] = 0;
            timelockCalldatas[0] = abi.encodeWithSelector(
                timelockDestChain.scheduleBatch.selector,
                batchTargets,
                batchValues,
                batchCalldatas,
                bytes32(0),
                bytes32(0),
                timelockDelay
            );
        }

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Test Cross chain proposals (redue updateDelay to 200 + remove executor role) higher fee";

        uint256 feeLZ = 1 ether;
        targets[0] = address(sender);
        values[0] = feeLZ;
        calldatas[0] = abi.encodeWithSelector(
            sender.execute.selector,
            _getLZChainId(destChainId),
            abi.encode(timelockTargets, timelockValues, new string[](1), timelockCalldatas),
            abi.encodePacked(uint16(1), uint256(300000))
        );

        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        // uint256 proposalId = 0x7f3a7bfba6ab7cdc0f85cfaa8bc2b03178c4d28dabbf53a1908604d2cb2d6891;
        governor.castVote(proposalId, 1);

        governor.execute{ value: feeLZ }(targets, values, calldatas, keccak256(bytes(description)));
    }
}
