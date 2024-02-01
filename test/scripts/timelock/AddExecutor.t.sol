// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import "../../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract AddExecutorTest is ScriptHelpers {
    using stdJson for string;

    address constant newExecutor = address(0);

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
                payable(_chainToContract(chainId, ContractType.Timelock))
            );
            vm.selectFork(forkIdentifier[chainId]);
            bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();

            assertEq(timelock.hasRole(EXECUTOR_ROLE, newExecutor), true);

            // This check is only when you set the address(0) as executor
            vm.startPrank(whale);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockController.TimelockUnexpectedOperationState.selector,
                    keccak256(abi.encode(address(0), 0, nullBytes, bytes32(0), bytes32(0))),
                    bytes32(1 << uint8(TimelockController.OperationState.Ready))
                )
            );
            timelock.execute(address(0), 0, nullBytes, bytes32(0), bytes32(0));
            vm.stopPrank();
        }
    }
}
