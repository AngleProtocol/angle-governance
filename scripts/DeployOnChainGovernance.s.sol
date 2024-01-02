// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import "stringutils/strings.sol";
import "./Utils.s.sol";
import "oz/interfaces/IERC20.sol";

import { IveANGLEVotingDelegation } from "contracts/interfaces/IveANGLEVotingDelegation.sol";
import { deployMockANGLE, deployVeANGLE } from "./test/DeployANGLE.s.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { ERC20 } from "oz/token/ERC20/ERC20.sol";
import "contracts/interfaces/IveANGLE.sol";
import "../test/external/VyperDeployer.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
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
    ProposalSender public proposalSender;
    TimelockController public timelock;

    function run() external {
        // TODO can be modified to deploy on any chain
        uint256 srcChainId = CHAIN_GNOSIS;
        address safeMultiSig = SAFE_GNOSIS;
        // END

        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GNOSIS"), "m/44'/60'/0'/0/", 0);
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        vm.label(deployer, "Deployer");

        /*
        // If not already - deploy the voting tokens
        vyperDeployer = new VyperDeployer();
        vm.allowCheatcodes(address(vyperDeployer));
        (address _mockANGLE, , ) = deployMockANGLE();
        ANGLE = ERC20(_mockANGLE);

        (address _mockVeANGLE, , ) = deployVeANGLE(vyperDeployer, _mockANGLE, safeMultiSig);
        veANGLE = IveANGLE(_mockVeANGLE);

        // Deploy Governance source chain
        token = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");
        */
        token = VeANGLEVotingDelegation(0xD622c71aba9060F393FEC67D3e2B9335292bf23B);

        address[] memory proposers = new address[](2);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute
        proposers[0] = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185;
        proposers[1] = 0x9d159aEb0b2482D09666A5479A2e426Cb8B5D091;
        timelock = new TimelockController(timelockDelayTest, proposers, executors, address(deployer));
        angleGovernor = new AngleGovernor(
            token,
            address(timelock),
            initialVotingDelayTest,
            initialVotingPeriodTest,
            initialProposalThresholdTest,
            initialVoteExtensionTest,
            initialQuorumNumerator,
            initialShortCircuitNumerator,
            initialVotingDelayBlocksTest
        );
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(angleGovernor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), safeMultiSig);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(deployer));
        proposalSender = new ProposalSender(lzEndPoint(srcChainId));
        proposalSender.transferOwnership(address(angleGovernor));

        vm.stopBroadcast();
    }
}
