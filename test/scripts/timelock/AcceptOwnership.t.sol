// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract AcceptOwnershipTest is ScriptHelpers {
    using stdJson for string;

    uint256 constant newMinDelay = uint256(1 days) - 1;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];

            address timelock = _chainToContract(chainId, ContractType.Timelock);
            IAccessControlViewVyper veANGLE = IAccessControlViewVyper(_chainToContract(chainId, ContractType.veANGLE));
            IAccessControlViewVyper smartWallet = IAccessControlViewVyper(
                _chainToContract(chainId, ContractType.SmartWalletWhitelist)
            );
            IAccessControlViewVyper veBoostProxy = IAccessControlViewVyper(
                _chainToContract(chainId, ContractType.veBoostProxy)
            );
            IAccessControlViewVyper gaugeController = IAccessControlViewVyper(
                _chainToContract(chainId, ContractType.GaugeController)
            );
            IAccessControlViewVyper gaugeSushi = IAccessControlViewVyper(0xBa625B318483516F7483DD2c4706aC92d44dBB2B);

            vm.selectFork(forkIdentifier[chainId]);

            assertEq(timelock, veANGLE.admin());
            assertEq(timelock, smartWallet.admin());
            assertEq(timelock, veBoostProxy.admin());
            assertEq(timelock, gaugeController.admin());
            assertEq(timelock, gaugeSushi.admin());
        }
    }
}
