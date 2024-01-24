// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IVaultManagerFunctions } from "borrow/interfaces/IVaultManager.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";

import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";

contract SetMinDelayTimelock is Wrapper {
    SubCall[] private subCalls;

    function _setMinDelay(uint256 chainId, uint256 minDelay) private {
        vm.selectFork(forkIdentifier[chainId]);
        address timelock = _chainToContract(chainId, ContractType.Timelock);

        subCalls.push(
            SubCall(chainId, timelock, 0, abi.encodeWithSelector(TimelockController.updateDelay.selector, minDelay))
        );
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmaWGR4XjsXHfaPxRB3UUX8DML56sg9dZLFCuvgpXzMiPC";

        /** TODO  complete */
        uint256 minDelay = uint256(1 days) - 1;
        /** END  complete */

        for (uint256 i = 0; i < chainIds.length; i++) {
            _setMinDelay(chainIds[i], minDelay);
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
