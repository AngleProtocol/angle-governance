// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { LzApp } from "lz/lzApp/LzApp.sol";
import { OFTCore } from "lz/token/oft/v1/OFTCore.sol";
import { Wrapper } from "../Wrapper.s.sol";
import { AgTokenSideChainMultiBridge } from "borrow/agToken/AgTokenSideChainMultiBridge.sol";
import "../../Constants.s.sol";

contract ConnectAgTokenSideChainMultiBridge is Wrapper {
    SubCall[] private subCalls;

    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");

        /** TODO  complete */
        string memory description = vm.envString("DESCRIPTION");
        address token = vm.envAddress("TOKEN");
        address lzToken = vm.envAddress("LZ_TOKEN");
        string memory stableName = vm.envString("STABLE_NAME");
        uint256 totalLimit = vm.envUint("TOTAL_LIMIT");
        uint256 hourlyLimit = vm.envUint("HOURLY_LIMIT");
        uint256 chainTotalHourlyLimit = vm.envUint("CHAIN_TOTAL_HOURLY_LIMIT");
        bool mock = vm.envOr("MOCK", false);
        /** END  complete */

        (uint256[] memory chainIds, address[] memory contracts) = _getConnectedChains(stableName);
        if (!mock) {
            subCalls.push(
                SubCall({
                    chainId: chainId,
                    target: token,
                    value: 0,
                    data: abi.encodeWithSelector(
                        AgTokenSideChainMultiBridge.addBridgeToken.selector,
                        lzToken,
                        totalLimit,
                        hourlyLimit,
                        0,
                        false
                    )
                })
            );

            subCalls.push(
                SubCall({
                    chainId: chainId,
                    target: lzToken,
                    value: 0,
                    data: abi.encodeWithSelector(
                        AgTokenSideChainMultiBridge.setChainTotalHourlyLimit.selector,
                        chainTotalHourlyLimit
                    )
                })
            );

            subCalls.push(
                SubCall({
                    chainId: chainId,
                    target: lzToken,
                    value: 0,
                    data: abi.encodeWithSelector(OFTCore.setUseCustomAdapterParams.selector, 1)
                })
            );

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
