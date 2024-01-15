// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import "transmuter/transmuter/Storage.sol" as Storage;
import { ISettersGuardian } from "transmuter/interfaces/ISetters.sol";

import { Wrapper } from "../Wrapper.s.sol";
import "../Constants.s.sol";

contract PauseTransmuter is Wrapper {
    SubCall[] private subCalls;

    function _pauseTransmuter(uint256 chainId) private {
        ITransmuter transmuter = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgEUR));

        address[] memory collateralList = transmuter.getCollateralList();

        {
            bytes memory data = abi.encodeWithSelector(
                ISettersGuardian.togglePause.selector,
                address(0x0),
                Storage.ActionType.Redeem
            );
            subCalls.push(SubCall(chainId, address(transmuter), 0, data));
        }
        for (uint256 i = 0; i < collateralList.length; i++) {
            address collateral = collateralList[i];
            console.log("Pausing %s", collateral);
            {
                bytes memory data = abi.encodeWithSelector(
                    ISettersGuardian.togglePause.selector,
                    collateral,
                    Storage.ActionType.Mint
                );
                subCalls.push(SubCall(chainId, address(transmuter), 0, data));
            }
            {
                bytes memory data = abi.encodeWithSelector(
                    ISettersGuardian.togglePause.selector,
                    collateral,
                    Storage.ActionType.Burn
                );
                subCalls.push(SubCall(chainId, address(transmuter), 0, data));
            }
        }
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "Pause transmuter";

        for (uint256 i = 0; i < chainIds.length; i++) {
            _pauseTransmuter(chainIds[i]);
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
