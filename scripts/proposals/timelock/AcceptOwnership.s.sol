// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";

import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";

contract AcceptOwnership is Wrapper {
    SubCall[] private subCalls;

    function _acceptOwnership(uint256 chainId) private {
        if (chainId == CHAIN_ETHEREUM) {
            vm.selectFork(forkIdentifier[chainId]);
            address veANGLE = _chainToContract(chainId, ContractType.veANGLE);
            address smartWallet = _chainToContract(chainId, ContractType.SmartWalletWhitelist);
            address veBoostProxy = _chainToContract(chainId, ContractType.veBoostProxy);
            address gaugeController = _chainToContract(chainId, ContractType.GaugeController);
            address gaugeSushi = 0xBa625B318483516F7483DD2c4706aC92d44dBB2B;

            subCalls.push(
                SubCall(
                    chainId,
                    veANGLE,
                    0,
                    abi.encodeWithSelector(IAccessControlWriteVyper.accept_transfer_ownership.selector)
                )
            );
            // TODO needs to be called by current admin
            // subCalls.push(
            //     SubCall(chainId, smartWallet, 0, abi.encodeWithSelector(ISmartWalletWhitelist.applyAdmin.selector))
            // );
            subCalls.push(
                SubCall(
                    chainId,
                    veBoostProxy,
                    0,
                    abi.encodeWithSelector(IAccessControlWriteVyper.accept_transfer_ownership.selector)
                )
            );
            subCalls.push(
                SubCall(
                    chainId,
                    gaugeController,
                    0,
                    abi.encodeWithSelector(IAccessControlWriteVyper.accept_transfer_ownership.selector)
                )
            );
            subCalls.push(
                SubCall(
                    chainId,
                    gaugeSushi,
                    0,
                    abi.encodeWithSelector(IAccessControlWriteVyper.accept_transfer_ownership.selector)
                )
            );
        }
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmecwSjj6LAXrgSPuGxfVLiTZtcamPuXRMckASTaFZSD9x";

        for (uint256 i = 0; i < chainIds.length; i++) {
            _acceptOwnership(chainIds[i]);
        }

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            uint256[] memory chainIds2
        ) = _wrap(subCalls);

        _serializeJson(targets, values, calldatas, chainIds2, description);
    }
}
