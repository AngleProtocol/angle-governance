// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { LzApp } from "lz/lzApp/LzApp.sol";
import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";

contract ConnectAngleSideChainMultiBridge is Wrapper {
    SubCall[] private subCalls;

    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");

        /** TODO  complete */
        string memory description = vm.envString("DESCRIPTION");
        bool mock = vm.envOr("MOCK", false);
        /** END  complete */

        string memory json = vm.readFile(JSON_ADDRESSES_PATH);
        address lzToken = vm.parseJsonAddress(json, ".lzAngle");

        (uint256[] memory chainIds, address[] memory contracts) = _getConnectedChains("ANGLE");

        if (!mock) {
            // Set trusted remote from current chain
            for (uint256 i = 0; i < contracts.length; i++) {
                if (chainIds[i] == chainId) {
                    continue;
                }

                subCalls.push(
                    SubCall(
                        chainId,
                        lzToken,
                        0,
                        abi.encodeWithSelector(
                            LzApp.setTrustedRemote.selector,
                            _getLZChainId(chainIds[i]),
                            abi.encodePacked(contracts[i], lzToken)
                        )
                    )
                );
            }
        }

        // Set trusted remote from all connected chains
        for (uint256 i = 0; i < contracts.length; i++) {
            if (chainIds[i] == chainId) {
                continue;
            }

            subCalls.push(
                SubCall(
                    chainIds[i],
                    contracts[i],
                    0,
                    abi.encodeWithSelector(
                        LzApp.setTrustedRemote.selector,
                        _getLZChainId(chainId),
                        abi.encodePacked(lzToken, contracts[i])
                    )
                )
            );
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
