// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { ITreasury, Utils } from "../Utils.s.sol";
import { IVaultManagerGovernance } from "scripts/Interfaces.s.sol";
import "../Constants.s.sol";

contract SetRateVaultManager is Utils {
    SubCall[] private subCalls;

    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");

        ITreasury treasury = ITreasury(_chainToContract(chainId, ContractType.TreasuryAgEUR));

        string memory description = "Set rate for all vaults";

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

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _wrap(subCalls);
        _serializeJson(chainId, targets, values, calldatas, description);
    }
}
