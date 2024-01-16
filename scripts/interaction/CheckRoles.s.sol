// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { ITreasury } from "borrow/interfaces/ITreasury.sol";
import { IAgToken } from "borrow/interfaces/IAgToken.sol";
import { IAccessControlManager } from "borrow/interfaces/IAccessControlManager.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";
import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

contract CheckRoles is Utils {
    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");

        for (uint256 i = 0; i < chainIds.length; i++) {
            _checkRoles(chainIds[i]);
        }
    }

    function _checkRoles(uint256 chainId) {
        vm.selectFork(forkIdentifier[chainId]);

        address[] memory listAddressToCheck = new address[](5);
        listAddressToCheck[0] = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185; // deployer
        listAddressToCheck[1] = 0xcC617C6f9725eACC993ac626C7efC6B96476916E; // keeper
        listAddressToCheck[2] = 0x5EB715d601C2F27f83Cb554b6B36e047822fB70a; // keeper Polygon
        listAddressToCheck[3] = 0xEd42E58A303E20523A695CB31ac31df26C50397B; // keeper Polygon 2
        listAddressToCheck[4] = 0x435046800Fb9149eE65159721A92cB7d50a7534b; // merkl keeper
        listAddressToCheck[5] = _chainToContract(chainId, ContractType.GovernorMultisig);
        listAddressToCheck[6] = _chainToContract(chainId, ContractType.GuardianMultisig);
        listAddressToCheck[7] = _chainToContract(chainId, ContractType.Governor);
        listAddressToCheck[8] = _chainToContract(chainId, ContractType.CoreBorrow);
        listAddressToCheck[9] = _chainToContract(chainId, ContractType.ProxyAdmin);

        IAgToken agToken = IAgToken(_chainToContract(chainId, ContractType.AgEUR));
        IAccessControlManager stEUR = IAccessControlManager(_chainToContract(chainId, ContractType.StEUR));
        IAngle angle = IAngle(_chainToContract(chainId, ContractType.Angle));
        IVeAngle veAngle = IAngle(_chainToContract(chainId, ContractType.veANGLE));

        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));

        bytes32 governorRole = core.GOVERNOR_ROLE();
        bytes32 guardianRole = core.GUARDIAN_ROLE();

        if (
            chainId == CHAIN_ETHEREUM ||
            chainId == CHAIN_POLYGON ||
            chainId == CHAIN_ARBITRUM ||
            chainId == CHAIN_OPTIMISM ||
            chainId == CHAIN_AVALANCHE ||
            chainId == CHAIN_BNB
        ) {
            {
                ITreasury treasury = ITreasury(payable(_chainToContract(chainId, ContractType.TreasuryAgEUR)));
                console.log("Treasury agEUR minter role: ", treasury.hasRole(treasury.MINTER_ROLE(), address(core)));
            }

            /** Remove minting agEUR privilege from the governance multisig  */
            {
                to = _chainToContract(chainId, ContractType.TreasuryAgEUR);
                bytes memory data = abi.encodeWithSelector(
                    ITreasuryWithRole.removeMinter.selector,
                    address(_chainToContract(chainId, ContractType.GovernorMultisig))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }
        }

        /** Add coreBorrow privilege to the on chain governance */
        {
            to = _chainToContract(chainId, ContractType.CoreBorrow);
            bytes memory data = abi.encodeWithSelector(
                CoreBorrow.addGovernor.selector,
                address(_chainToContract(chainId, ContractType.Governor))
            );
            uint256 dataLength = data.length;
            bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
            transactions = abi.encodePacked(transactions, internalTx);
        }

        // /** Remove coreBorrow privilege from the governor multisig */
        // {
        //     to = _chainToContract(chainId, ContractType.CoreBorrow);
        //     bytes memory data = abi.encodeWithSelector(
        //         CoreBorrow.removeGovernor.selector,
        //         address(_chainToContract(chainId, ContractType.GovernorMultisig))
        //     );
        //     uint256 dataLength = data.length;
        //     bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
        //     transactions = abi.encodePacked(transactions, internalTx);
        // }

        // /** Remove proxy admin privilege from the governance multisig  */
        // {
        //     to = _chainToContract(chainId, ContractType.ProxyAdmin);
        //     bytes memory data = abi.encodeWithSelector(
        //         Ownable.transferOwnership.selector,
        //         address(_chainToContract(chainId, ContractType.Governor))
        //     );
        //     uint256 dataLength = data.length;
        //     bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
        //     transactions = abi.encodePacked(transactions, internalTx);
        // }

        if (chainId == CHAIN_ETHEREUM) {
            {
                to = _chainToContract(chainId, ContractType.Angle);
                bytes memory data = abi.encodeWithSelector(
                    IAngle.setMinter.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Propose a new admin 
                On chain governance will have to accept it
                Better in this way to verify this address is valid and can accept it
             */
            {
                to = _chainToContract(chainId, ContractType.veANGLE);
                bytes memory data = abi.encodeWithSelector(
                    IVeAngle.commit_transfer_ownership.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Change veANGLE smart wallet whitelist admin */
            {
                to = _chainToContract(chainId, ContractType.SmartWalletWhitelist);
                bytes memory data = abi.encodeWithSelector(
                    ISmartWalletWhitelist.commitAdmin.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Change veBoostProxy admin */
            {
                to = _chainToContract(chainId, ContractType.veBoostProxy);
                bytes memory data = abi.encodeWithSelector(
                    IVeBoostProxy.commit_admin.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Change Gauge Controller admin */
            {
                to = _chainToContract(chainId, ContractType.GaugeController);
                bytes memory data = abi.encodeWithSelector(
                    IGaugeController.commit_transfer_ownership.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Change Gauge Sushi ANGLE-agEUR admin */
            {
                to = gaugeSushiAngleAgEUR;
                bytes memory data = abi.encodeWithSelector(
                    ILiquidityGauge.commit_transfer_ownership.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Add the on chain governor as governor of Angle Distributor  */
            {
                to = _chainToContract(chainId, ContractType.AngleDistributor);
                bytes memory data = abi.encodeWithSelector(
                    IAccessControl.grantRole.selector,
                    governorRole,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Add the on chain governor as guardian of Angle Distributor  */
            {
                to = _chainToContract(chainId, ContractType.AngleDistributor);
                bytes memory data = abi.encodeWithSelector(
                    IAccessControl.grantRole.selector,
                    guardianRole,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Remove the multisig as guardian of Angle Distributor  */
            {
                to = _chainToContract(chainId, ContractType.AngleDistributor);
                bytes memory data = abi.encodeWithSelector(
                    IAccessControl.revokeRole.selector,
                    guardianRole,
                    address(_chainToContract(chainId, ContractType.GovernorMultisig))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Remove the multisig as governor of Angle Distributor  */
            {
                to = _chainToContract(chainId, ContractType.AngleDistributor);
                bytes memory data = abi.encodeWithSelector(
                    IAccessControl.revokeRole.selector,
                    governorRole,
                    address(_chainToContract(chainId, ContractType.GovernorMultisig))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Add the on chain governor as governor of Angle Middleman */
            {
                to = _chainToContract(chainId, ContractType.AngleMiddleman);
                bytes memory data = abi.encodeWithSelector(
                    IAccessControl.grantRole.selector,
                    guardianRole,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            /** Remove the multisig as guardian of Angle Distributor  */
            {
                to = _chainToContract(chainId, ContractType.AngleMiddleman);
                bytes memory data = abi.encodeWithSelector(
                    IAccessControl.revokeRole.selector,
                    guardianRole,
                    address(_chainToContract(chainId, ContractType.GovernorMultisig))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            // /** Change Fee Distributor admin */
            // {
            //     to = _chainToContract(chainId, ContractType.FeeDistributor);
            //     bytes memory data = abi.encodeWithSelector(
            //         IFeeDistributor.commit_admin.selector,
            //         address(_chainToContract(chainId, ContractType.Governor))
            //     );
            //     uint256 dataLength = data.length;
            //     bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
            //     transactions = abi.encodePacked(transactions, internalTx);
            // }
        }
    }
}
