// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";

import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

contract SavingsSetRate is Utils {
    SubCall[] private subCalls;

    function _setRateSavings(uint256 chainId, uint208 rate) private {
        vm.selectFork(forkIdentifier[chainId]);
        address stEUR = _chainToContract(chainId, ContractType.StEUR);

        subCalls.push(SubCall(chainId, stEUR, 0, abi.encodeWithSelector(ISavings.setRate.selector, rate)));
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "Set rate for all savings";

        /** TODO  complete */
        uint208 rate = uint208(uint256(fourPoint3Rate));
        /** END  complete */

        for (uint256 i = 0; i < chainIds.length; i++) {
            _setRateSavings(chainIds[i], rate);
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _wrap(subCalls);
        _serializeJson(targets, values, calldatas, description);
    }
}
