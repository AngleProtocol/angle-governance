// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { ITreasury, Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

/** This script suppose that the state of all the vaultManager on the chain are identical (all paused or unpause) 
/** Otherwise behaviour is chaotic
*/
contract PauseVaultManagers is Utils {
    SubCall[] private subCalls;

    function run() external {
        bytes memory transactions;
        uint8 isDelegateCall = 0;
        uint256 value = 0;
        string memory description = "Pause all vault managers";

        uint256 chainId = vm.envUint("CHAIN_ID");

        ITreasury treasury = ITreasury(_chainToContract(chainId, ContractType.TreasuryAgEUR));
        uint256 i;
        while (true) {
            try treasury.vaultManagerList(i) returns (address vault) {
                string memory name = IERC721Metadata(vault).name();
                console.log("Pausing %s", name);
                {
                    subCalls.push(SubCall(chainId, vault, 0, abi.encode(IVaultManagerFunctions.togglePause.selector)));
                }
                i++;
            } catch {
                break;
            }
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _wrap(subCalls);
        _serializeJson(chainId, targets, values, calldatas, description);
    }
}
