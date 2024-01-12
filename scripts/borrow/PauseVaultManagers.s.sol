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

    function _pauseVaultManagers(uint256 chainId) private {
        vm.selectFork(forkIdentifier[chainId]);
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
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "Pause all vaults";

        for (uint256 i = 0; i < chainIds.length; i++) {
            _pauseVaultManagers(chainIds[i]);
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
