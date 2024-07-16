// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";

contract UpgradeAgTokenNameable is Wrapper {
    SubCall[] private subCalls;
    mapping(uint256 => address) private _chainToToken;
    mapping(uint256 => address) private _chainToImplementation;

    function _upgradeAgToken(
        uint256 chainId,
        string memory name,
        string memory symbol,
        address proxy,
        address implementation,
        address proxyAdmin
    ) private {
        vm.selectFork(forkIdentifier[chainId]);

        bytes memory nameAndSymbolData = abi.encodeWithSelector(INameable.setNameAndSymbol.selector, name, symbol);
        bytes memory data = abi.encodeWithSelector(ProxyAdmin.upgradeAndCall.selector, proxy, implementation, "");

        subCalls.push(SubCall(chainId, proxyAdmin, 0, data));
        subCalls.push(SubCall(chainId, proxy, 0, nameAndSymbolData));
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmRSdyuXeemVEn97RPRSiit6UEUonvwVr9we7bEe2w8v2E";

        /** TODO  complete */
        string memory name = "EURA"; // previously "agEUR"
        string memory symbol = "EURA"; // previously "agEUR"
        _chainToToken[CHAIN_ETHEREUM] = address(0);
        _chainToImplementation[CHAIN_ETHEREUM] = address(0);
        /** END  complete */

        for (uint256 i = 0; i < chainIds.length; i++) {
            address agToken = _chainToToken[chainIds[i]];
            address implementation = _chainToImplementation[chainIds[i]];
            address proxyAdmin = _chainToContract(chainIds[i], ContractType.ProxyAdmin);

            _upgradeAgToken(chainIds[i], name, symbol, agToken, implementation, proxyAdmin);
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
