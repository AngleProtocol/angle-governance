// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";

contract MintStablecoinTest is ScriptHelpers {
    using stdJson for string;

    mapping(uint256 => uint256) public prevBalances;
    uint256 constant amount = 5 * 10 ** 6 * 1 ether;
    uint256 constant prevValue = 3298919859209628675884005;
    address receiver;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            IAgToken USDA = IAgToken(payable(_chainToContract(chainId, ContractType.AgUSD)));
            receiver = 0x57eedCB68445355e9C11A90F39012e8d4AAA89Fc;
            // receiver = _chainToContract(chainId, ContractType.TreasuryAgUSD);
            vm.selectFork(forkIdentifier[chainId]);
            address timelock = _chainToContract(chainId, ContractType.Timelock);

            assertEq(USDA.isMinter(timelock), true);
            uint256 newBalance = USDA.balanceOf(receiver);
            // It suppose it doesn't own any USDA
            assertEq(amount, newBalance - prevValue);
        }
    }
}
