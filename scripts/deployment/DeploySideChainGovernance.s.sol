// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "../Utils.s.sol";
import "oz/interfaces/IERC20.sol";

import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ERC20 } from "oz/token/ERC20/ERC20.sol";

import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

/// @dev To deploy on a different chain, just replace the import of the `Constants.s.sol` file by a file which has the
/// constants defined for the chain of your choice.
contract DeploySideChainGovernance is Utils {
    using stdJson for string;
    using strings for *;

    ProposalReceiver public proposalReceiver;
    TimelockControllerWithCounter public timelock;

    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        // TODO can be modified to deploy on any chain
        uint256 srcChainId = CHAIN_ETHEREUM;
        uint256 destChainId = CHAIN_BLAST;
        address destSafeMultiSig = 0x7DE8289038DF0b89FFEC71Ee48a2BaD572549027; // guardian
        // END

        ProposalSender proposalSender = ProposalSender(_chainToContract(srcChainId, ContractType.ProposalSender));
        // Deploy relayer receiver and Timelock on end chain
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        timelock = new TimelockControllerWithCounter(timelockDelay, proposers, executors, deployer);
        console.log("Timelock address: ", address(timelock));

        proposalReceiver = new ProposalReceiver(address(_lzEndPoint(destChainId)));
        console.log("ProposalReceiver address: ", address(proposalReceiver));

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(proposalReceiver));
        timelock.grantRole(timelock.CANCELLER_ROLE(), destSafeMultiSig);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        proposalReceiver.setTrustedRemoteAddress(_getLZChainId(srcChainId), abi.encodePacked(proposalSender));
        proposalReceiver.transferOwnership(address(timelock));

        vm.stopBroadcast();

        // TODO to connect both chains - governance need to approve this relayer receiver on native chain
        // vm.selectFork(srcChainId);
        // proposalSender.setTrustedRemoteAddress(_getLZChainId(destChainId), abi.encodePacked(proposalReceiver));
    }
}
