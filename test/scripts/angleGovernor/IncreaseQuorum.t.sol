// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";

contract IncreaseQuorumTest is ScriptHelpers {
    using stdJson for string;

    uint256 public constant quorum = 20;
    uint256 public constant quorumShortCircuit = 75;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            AngleGovernor angleGovernor = AngleGovernor(payable(_chainToContract(chainId, ContractType.Governor)));
            vm.selectFork(forkIdentifier[chainId]);
            uint256 quorumOnChain = angleGovernor.quorumNumerator();
            uint256 quorumShortCircuitOnChain = angleGovernor.shortCircuitNumerator();
            assertEq(quorum, quorumOnChain);
            assertEq(quorumShortCircuit, quorumShortCircuitOnChain);
        }
    }
}
