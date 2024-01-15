// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import "transmuter/transmuter/Storage.sol" as Storage;
import { ISettersGuardian } from "transmuter/interfaces/ISetters.sol";

import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

contract TransmuterSetRedemptionParams is Utils {
    SubCall[] private subCalls;

    function setRedemptionParams(uint256 chainId, uint64[] memory xFee, int64[] memory yFee) private {
        ITransmuter transmuter = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgEUR));

        bytes memory data = abi.encodeWithSelector(ISettersGuardian.setRedemptionCurveParams.selector, xFee, yFee);
        subCalls.push(SubCall(chainId, address(transmuter), 0, data));
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "Set redemption params for transmuter";

        /** TODO  complete */
        uint64[] memory xFee = new uint64[](2);
        int64[] memory yFee = new int64[](2);

        xFee[0] = 0;
        xFee[1] = uint64(BASE_9);
        yFee[0] = 0;
        yFee[1] = 0;
        /** END  complete */

        for (uint256 i = 0; i < chainIds.length; i++) {
            setRedemptionParams(chainIds[i], xFee, yFee);
        }

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            uint256[] memory chainIds2
        ) = _wrap(subCalls);
    }
}
