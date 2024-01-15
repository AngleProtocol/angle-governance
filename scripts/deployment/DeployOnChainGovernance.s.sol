// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "../Utils.s.sol";
import "oz/interfaces/IERC20.sol";

import { IveANGLEVotingDelegation } from "contracts/interfaces/IveANGLEVotingDelegation.sol";
import { deployMockANGLE, deployVeANGLE } from "../test/DeployANGLE.s.sol";
import { ERC20 } from "oz/token/ERC20/ERC20.sol";
import "contracts/interfaces/IveANGLE.sol";
import "../../test/external/VyperDeployer.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { VeANGLEVotingDelegation, ECDSA } from "contracts/VeANGLEVotingDelegation.sol";

/// @dev To deploy on a different chain, just replace the import of the `Constants.s.sol` file by a file which has the
/// constants defined for the chain of your choice.
contract DeployOnChainGovernance is Utils {
    using stdJson for string;
    using strings for *;

    VyperDeployer public vyperDeployer;

    ERC20 public ANGLE;
    IveANGLE public veANGLE;
    VeANGLEVotingDelegation public token;
    AngleGovernor public angleGovernor;
    ProposalSender public proposalSenderDeployed;
    TimelockControllerWithCounter public timelock;

    function run() external {
        // TODO can be modified to deploy on any chain
        uint256 srcChainId = CHAIN_ETHEREUM;
        // END

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_MAINNET"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        address safeMultiSig = _chainToContract(srcChainId, ContractType.GuardianMultisig);
        veANGLE = IveANGLE(_chainToContract(srcChainId, ContractType.veANGLE));
        token = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = safeMultiSig; // Means everyone can execute
        timelock = new TimelockControllerWithCounter(timelockDelay, proposers, executors, address(deployer));
        angleGovernor = new AngleGovernor(
            token,
            address(timelock),
            initialVotingDelay,
            initialVotingPeriod,
            initialProposalThreshold,
            initialVoteExtension,
            initialQuorumNumerator,
            initialShortCircuitNumerator,
            initialVotingDelayBlocks
        );
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(angleGovernor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), safeMultiSig);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(deployer));
        proposalSenderDeployed = new ProposalSender(lzEndPoint(srcChainId));
        proposalSenderDeployed.transferOwnership(address(angleGovernor));
        vm.stopBroadcast();
    }
}
