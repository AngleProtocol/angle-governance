// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { ITreasury, Utils } from "../Utils.s.sol";
import { IVaultManagerGovernance } from "scripts/Interfaces.s.sol";
import "../Constants.s.sol";

contract SetRateVaultManager is Utils {
    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");

        ITreasury treasury = ITreasury(_chainToContract(chainId, ContractType.TreasuryAgEUR));

        bytes memory transactions;
        uint8 isDelegateCall = 0;
        uint256 value = 0;

        uint256 i;
        while (true) {
            try treasury.vaultManagerList(i) returns (address vault) {
                uint64 rate;
                /** TODO  complete */
                // Non yield bearing vaults
                if (i == 0 || i == 1 || i == 2) rate = twoPoint5Rate;
                else rate = fourRate;
                /** END  complete */

                string memory name = IERC721Metadata(vault).name();
                console.log("Setting rate %s", name);
                {
                    address to = vault;
                    bytes32 what = "IR";
                    bytes memory data = abi.encodeWithSelector(IVaultManagerGovernance.setUint64.selector, rate, what);
                    uint256 dataLength = data.length;
                    bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                    transactions = abi.encodePacked(transactions, internalTx);
                }
                i++;
            } catch {
                break;
            }
        }

        // bytes memory payloadMultiSend = abi.encodeWithSelector(MultiSend.multiSend.selector, transactions);
        //
        // address multiSend = address(_chainToMultiSend(chainId));
        // address guardian = address(_chainToContract(chainId, ContractType.GuardianMultisig));
        // // Verify that the calls will succeed
        // vm.startBroadcast(guardian);
        // address(multiSend).delegatecall(payloadMultiSend);
        // vm.stopBroadcast();

        // _serializeJson(chainId, multiSend, 0, payloadMultiSend, Enum.Operation.DelegateCall, hex"");
    }
}
