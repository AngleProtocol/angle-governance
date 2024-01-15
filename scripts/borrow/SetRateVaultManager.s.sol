// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { ITreasury, Wrapper } from "../Wrapper.s.sol";
import { IVaultManagerGovernance } from "scripts/Interfaces.s.sol";
import "../Constants.s.sol";

contract SetRateVaultManager is Wrapper {
    SubCall[] private subCalls;

    function _setRateVaultManager(uint256 chainId) internal {
        vm.selectFork(forkIdentifier[chainId]);
        ITreasury treasury = ITreasury(_chainToContract(chainId, ContractType.TreasuryAgEUR));

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
                    subCalls.push(
                        SubCall(
                            chainId,
                            vault,
                            0,
                            abi.encodeWithSelector(IVaultManagerGovernance.setUint64.selector, rate, "IR")
                        )
                    );
                }
                i++;
            } catch {
                break;
            }
        }
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "Set rate for all vaults";

        for (uint256 i = 0; i < chainIds.length; i++) {
            _setRateVaultManager(chainIds[i]);
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
