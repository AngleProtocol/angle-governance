// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "./ScriptHelpers.t.sol";
import "../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract SavingsSetRateTest is ScriptHelpers {
    using stdJson for string;

    uint256 constant newRate = fourPoint3Rate;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            ISavings stEUR = ISavings(payable(_chainToContract(chainId, ContractType.StEUR)));
            vm.selectFork(forkIdentifier[chainId]);
            uint256 rate = stEUR.rate();
            assertEq(rate, newRate);
        }
    }
}
