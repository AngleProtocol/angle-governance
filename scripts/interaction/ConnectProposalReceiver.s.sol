// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "../Utils.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract ConnectProposalReceiver is Utils {
    function run() external {
        // TODO can be modified to deploy on any chain
        uint256 destChainId = CHAIN_POLYGON;
        // END

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Add new proposal Receiver on Polygon";

        ProposalSender sender = proposalSender();
        targets[0] = address(sender);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(
            sender.setTrustedRemoteAddress.selector,
            getLZChainId(destChainId),
            abi.encodePacked(proposalReceiverPolygon)
        );

        // uint256 proposalId = governor().propose(targets, values, calldatas, description);

        // uint256 proposalId = 0x16ce056680a50ff416e0f846aa4e1e5d86461daafe597cdaed44776e850c2869;
        // governor().castVote(proposalId, 1);

        governor().execute(targets, values, calldatas, keccak256(bytes(description)));
    }
}
