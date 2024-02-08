// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";
import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";

contract AddExecutor is Wrapper {
    SubCall[] private subCalls;

    function _addExecutorRole(uint256 chainId, address executor) private {
        vm.selectFork(forkIdentifier[chainId]);
        address timelock = _chainToContract(chainId, ContractType.Timelock);

        bytes32 EXECUTOR_ROLE = TimelockController(payable(timelock)).EXECUTOR_ROLE();
        subCalls.push(
            SubCall(
                chainId,
                timelock,
                0,
                abi.encodeWithSelector(IAccessControl.grantRole.selector, EXECUTOR_ROLE, executor)
            )
        );
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmYv2RGPpZh78vCsQPd6R4HMJcGH61Mi2oL5a4eXMei61n";

        /** TODO  complete */
        address executor = address(0);
        /** END  complete */

        for (uint256 i = 0; i < chainIds.length; i++) {
            _addExecutorRole(chainIds[i], executor);
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
