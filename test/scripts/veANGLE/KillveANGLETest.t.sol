// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

contract KillveANGLETest is ScriptHelpers {
    using stdJson for string;
    mapping(uint256 => address) private _chainToToken;

    function setUp() public override {
        super.setUp();
    }

    function run() external {
        testScript();
    }

    function testScript() public {
        uint256[] memory chainIds = _executeProposal();
        vm.selectFork(forkIdentifier[1]);

        address veANGLE = 0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5;
        address timelock = 0x09D81464c7293C774203E46E3C921559c8E9D53f;
        address proposalSender = 0x896D64B4B7265273dDCD00808f3579563f9790A8;
        address onchainGovernorContract = 0x748bA9Cd5a5DDba5ABA70a4aC861b2413dCa4436;
        address govMultisig = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;

        bytes32 PROPOSER_ROLE = TimelockController(payable(timelock)).PROPOSER_ROLE();
        bytes32 CANCELLER_ROLE = TimelockController(payable(timelock)).CANCELLER_ROLE();
        bytes32 EXECUTOR_ROLE = TimelockController(payable(timelock)).EXECUTOR_ROLE();

        assertEq(IVeAngle(veANGLE).emergency_withdrawal(), true);
        assertEq(IOwnable(proposalSender).owner(), govMultisig);
        assertEq(IAccessControl(timelock).hasRole(PROPOSER_ROLE, onchainGovernorContract), false);
        assertEq(IAccessControl(timelock).hasRole(PROPOSER_ROLE, govMultisig), true);
        assertEq(IAccessControl(timelock).hasRole(CANCELLER_ROLE, govMultisig), true);
        assertEq(IAccessControl(timelock).hasRole(EXECUTOR_ROLE, address(0)), true);
    }
}
