// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { ITreasury } from "borrow/interfaces/ITreasury.sol";
import { IAgToken } from "borrow/interfaces/IAgToken.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

// 1,2,3,4,5,6,7,8,9,10,11
contract CheckRoles is Utils {
    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");

        for (uint256 i = 0; i < chainIds.length; i++) {
            _checkRoles(chainIds[i]);
        }
    }

    function _checkRoles(uint256 chainId) internal {
        vm.selectFork(forkIdentifier[chainId]);

        // Address to check roles for
        address[] memory listAddressToCheck = new address[](11);
        listAddressToCheck[0] = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185; // deployer
        listAddressToCheck[1] = 0xcC617C6f9725eACC993ac626C7efC6B96476916E; // keeper
        listAddressToCheck[2] = 0x5EB715d601C2F27f83Cb554b6B36e047822fB70a; // keeper Polygon
        listAddressToCheck[3] = 0xEd42E58A303E20523A695CB31ac31df26C50397B; // keeper Polygon 2
        listAddressToCheck[4] = 0x435046800Fb9149eE65159721A92cB7d50a7534b; // merkl keeper
        // listAddressToCheck[5] = _chainToContract(chainId, ContractType.GovernorMultisig);
        // listAddressToCheck[6] = _chainToContract(chainId, ContractType.GuardianMultisig);
        // listAddressToCheck[7] = _chainToContract(chainId, ContractType.Governor);
        listAddressToCheck[8] = _chainToContract(chainId, ContractType.CoreBorrow);
        listAddressToCheck[9] = _chainToContract(chainId, ContractType.ProxyAdmin);
        listAddressToCheck[10] = _chainToContract(chainId, ContractType.Timelock);

        {
            // Contract to check roles on
            IAngle angle = IAngle(_chainToContract(chainId, ContractType.Angle));
            ProposalSender proposalSender = ProposalSender(
                payable(_chainToContract(chainId, ContractType.ProposalSender))
            );
            ProposalReceiver proposalReceiver = ProposalReceiver(
                payable(_chainToContract(chainId, ContractType.ProposalReceiver))
            );
            ProxyAdmin proxyAdmin = ProxyAdmin(_chainToContract(chainId, ContractType.ProxyAdmin));

            console.log("Angle - minter role: ", angle.minter());
            console.log("Proposal Sender - owner: ", proposalSender.owner());
            console.log("Proposal Receiver - owner: ", proposalReceiver.owner());
            console.log("Proxy Admin - owner: ", proxyAdmin.owner());

            if (chainId == CHAIN_ETHEREUM) {
                // Contract to check roles on
                IGaugeController gaugeController = IGaugeController(
                    _chainToContract(chainId, ContractType.GaugeController)
                );
                ISmartWalletWhitelist smartWalletWhitelist = ISmartWalletWhitelist(
                    _chainToContract(chainId, ContractType.SmartWalletWhitelist)
                );
                IVeAngle veAngle = IVeAngle(_chainToContract(chainId, ContractType.veANGLE));
                IVeBoost veBoost = IVeBoost(_chainToContract(chainId, ContractType.veBoost));
                IVeBoostProxy veBoostProxy = IVeBoostProxy(_chainToContract(chainId, ContractType.veBoostProxy));

                console.log("Gauge Controller - admin role: ", gaugeController.admin());
                console.log("Gauge Controller - future admin role: ", gaugeController.future_admin());
                console.log("Smart Wallet Whitelist - admin: ", smartWalletWhitelist.admin());
                console.log("Smart Wallet Whitelist - future admin: ", smartWalletWhitelist.future_admin());
                console.log("veANGLE - admin: ", veAngle.admin());
                console.log("veANGLE - future admin: ", veAngle.future_admin());
                console.log("veBoost - admin: ", veBoost.admin());
                console.log("veBoost - future admin: ", veBoost.future_admin());
                console.log("veBoostProxy - admin: ", veBoostProxy.admin());
                console.log("veBoostProxy - future admin: ", veBoostProxy.future_admin());
            }
        }

        // Contract to check roles on
        IAgToken agEUR = IAgToken(_chainToContract(chainId, ContractType.AgEUR));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
            payable(_chainToContract(chainId, ContractType.Timelock))
        );
        for (uint256 i = 0; i < listAddressToCheck.length; i++) {
            address actor = listAddressToCheck[i];
            console.log("Actor: ", actor);

            console.log("AgEUR - minter role: ", agEUR.isMinter(actor));
            console.log("Core Borrow - governor role: ", core.hasRole(core.GOVERNOR_ROLE(), actor));
            console.log("Core Borrow - guardian role: ", core.hasRole(core.GUARDIAN_ROLE(), actor));
            console.log("Core Borrow - flashloan role: ", core.hasRole(core.FLASHLOANER_TREASURY_ROLE(), actor));
            console.log("Timelock - proposer role: ", timelock.hasRole(timelock.PROPOSER_ROLE(), actor));
            console.log("Timelock - canceller role: ", timelock.hasRole(timelock.CANCELLER_ROLE(), actor));
            console.log("Timelock - executor role: ", timelock.hasRole(timelock.EXECUTOR_ROLE(), actor));
            console.log("Timelock - default admin role: ", timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), actor));

            if (chainId == CHAIN_ETHEREUM) {
                IAccessControl angleDistributor = IAccessControl(
                    _chainToContract(chainId, ContractType.AngleDistributor)
                );
                console.log(
                    "Angle distributor - governor role: ",
                    angleDistributor.hasRole(core.GOVERNOR_ROLE(), actor)
                );
                console.log(
                    "Angle distributor - guardian role: ",
                    angleDistributor.hasRole(core.GUARDIAN_ROLE(), actor)
                );
            }
        }
    }
}
