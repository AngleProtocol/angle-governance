// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";
import { Treasury } from "borrow/Treasury/Treasury.sol";

contract MintStablecoin is Wrapper {
    SubCall[] private subCalls;
    address private receiver;

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmdqXrJuwMgXqThycomvxGVLpBFpxFbsWgWey3Qi7THDYF";

        /** TODO  complete */
        uint256 amount = 5 * 10 ** 6 * 1 ether;
        /** END  complete */

        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            vm.selectFork(forkIdentifier[chainId]);
            address USDA = _chainToContract(chainId, ContractType.AgUSD);
            address receiver = 0x57eedCB68445355e9C11A90F39012e8d4AAA89Fc;
            address USDATreasury = _chainToContract(chainId, ContractType.TreasuryAgUSD);
            address timelock = _chainToContract(chainId, ContractType.Timelock);
            subCalls.push(
                SubCall(chainId, USDATreasury, 0, abi.encodeWithSelector(Treasury.addMinter.selector, timelock))
            );
            subCalls.push(SubCall(chainId, USDA, 0, abi.encodeWithSelector(IAgToken.mint.selector, receiver, amount)));
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
