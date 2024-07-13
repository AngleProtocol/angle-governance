// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

contract SavingsSetRateTest is ScriptHelpers {
    using stdJson for string;
    mapping(uint256 => address) private _chainToToken;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

         /** TODO  complete */
        string memory name = "EURA";
        string memory symbol = "EURA";
        _chainToToken[CHAIN_ETHEREUM] = address(0);
        /** END  complete */

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            IERC20Metadata agToken = IERC20Metadata(_chainToToken[chainId]);
            vm.selectFork(forkIdentifier[chainId]);
            assertEq(agToken.name(), name);
            assertEq(agToken.symbol(), symbol);
        }
    }
}
