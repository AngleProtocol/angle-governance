// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";

import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

contract SavingsSetRate is Utils {
    function run() external {
        bytes memory transactions;
        uint8 isDelegateCall = 0;
        uint256 value = 0;

        uint256 chainId = vm.envUint("CHAIN_ID");

        /** TODO  complete */
        uint208 rate = uint208(uint256(fourPoint3Rate));
        /** END  complete */
        address stEUR = _chainToContract(chainId, ContractType.StEUR);

        bytes memory data = abi.encodeWithSelector(ISavings.setRate.selector, rate);
        uint256 dataLength = data.length;
        address to = stEUR;
        bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
        transactions = abi.encodePacked(transactions, internalTx);

        // bytes memory payloadMultiSend = abi.encodeWithSelector(MultiSend.multiSend.selector, transactions);

        // // Verify that the calls will succeed
        // address multiSend = address(_chainToMultiSend(chainId));
        // address guardian = address(_chainToContract(chainId, ContractType.GuardianMultisig));
        // vm.startBroadcast(guardian);
        // address(multiSend).delegatecall(payloadMultiSend);
        // vm.stopBroadcast();
        // _serializeJson(chainId, multiSend, 0, payloadMultiSend, Enum.Operation.DelegateCall, data);
    }
}
