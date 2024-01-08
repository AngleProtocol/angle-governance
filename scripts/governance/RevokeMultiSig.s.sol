// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { IAgToken } from "borrow/interfaces/IAgToken.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";

import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

interface ITreasuryWithRole {
    function addMinter(address minter) external;

    function removeMinter(address minter) external;
}

contract RevokeMultiSig is Utils {
    address public gaugeSushiAngleAgEUR = 0xBa625B318483516F7483DD2c4706aC92d44dBB2B;

    function run() external {
        bytes memory transactions;
        uint8 isDelegateCall = 0;
        uint256 value = 0;
        address to;
        /** TODO  complete */
        uint256 chainId = CHAIN_ETHEREUM;
        /** END  complete */
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
            /** Add minting agEUR privilege to the on chain governance */
            {
                to = _chainToContract(chainId, ContractType.TreasuryAgEUR);
                bytes memory data = abi.encodeWithSelector(
                    ITreasuryWithRole.addMinter.selector,
                    address(_chainToContract(chainId, ContractType.Governor))
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
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
        // bytes memory payloadMultiSend = abi.encodeWithSelector(MultiSend.multiSend.selector, transactions);
        // address multiSend = address(_chainToMultiSend(chainId));
        // _serializeJson(chainId, multiSend, 0, payloadMultiSend, Enum.Operation.DelegateCall, hex"");
    }
}
