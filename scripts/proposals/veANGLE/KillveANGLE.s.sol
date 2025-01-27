// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";
import { ProxyAdmin } from "oz/proxy/transparent/ProxyAdmin.sol";

contract KillveANGLE is Wrapper {
    SubCall[] private subCalls;
    uint256 public constant chainId = CHAIN_ETHEREUM;

    function run() external {
        vm.selectFork(forkIdentifier[chainId]);
        address veANGLE = 0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5;
        address timelock = 0x09D81464c7293C774203E46E3C921559c8E9D53f;
        address proposalSender = 0x896D64B4B7265273dDCD00808f3579563f9790A8;
        address onchainGovernorContract = 0x748bA9Cd5a5DDba5ABA70a4aC861b2413dCa4436;
        address govMultisig = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;

        // Activate veANGLE emergency withdrawal
        subCalls.push(SubCall(chainId, veANGLE, 0, abi.encodeWithSelector(IVeAngle.set_emergency_withdrawal.selector)));

        // Granting the proposer role to governance msig
        subCalls.push(
            SubCall(
                chainId,
                timelock,
                0,
                abi.encodeWithSelector(
                    IAccessControl.grantRole.selector,
                    TimelockController(payable(timelock)).PROPOSER_ROLE(),
                    govMultisig
                )
            )
        );

        // Granting the canceller role to governance msig
        subCalls.push(
            SubCall(
                chainId,
                timelock,
                0,
                abi.encodeWithSelector(
                    IAccessControl.grantRole.selector,
                    TimelockController(payable(timelock)).CANCELLER_ROLE(),
                    govMultisig
                )
            )
        );

        // Revoking the proposer role to the governor contract
        subCalls.push(
            SubCall(
                chainId,
                timelock,
                0,
                abi.encodeWithSelector(
                    IAccessControl.revokeRole.selector,
                    TimelockController(payable(timelock)).PROPOSER_ROLE(),
                    onchainGovernorContract
                )
            )
        );

        // TODO: change description

        string memory description = "ipfs://QmS6WCqc8pA44jJKFyXw8en1qDKkiXCdGPsWamruQyeSY2";

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            uint256[] memory chainIds2
        ) = _wrap(subCalls);

        // Create new arrays with length + 1
        address[] memory newTargets = new address[](targets.length + 1);
        uint256[] memory newValues = new uint256[](values.length + 1);
        bytes[] memory newCalldatas = new bytes[](calldatas.length + 1);
        uint256[] memory newChainIds = new uint256[](chainIds2.length + 1);

        // Need to switch proposalSender owner

        newTargets[0] = proposalSender;
        newValues[0] = 0;
        newCalldatas[0] = abi.encodeWithSelector(IOwnable.transferOwnership.selector, govMultisig);
        newChainIds[0] = 1;

        // Copy the rest of the elements
        for (uint256 i = 0; i < targets.length; i++) {
            newTargets[i + 1] = targets[i];
            newValues[i + 1] = values[i];
            newCalldatas[i + 1] = calldatas[i];
            newChainIds[i + 1] = chainIds2[i];
        }

        // Reassign the arrays
        targets = newTargets;
        values = newValues;
        calldatas = newCalldatas;
        chainIds2 = newChainIds;

        _serializeJson(targets, values, calldatas, chainIds2, description);
    }
}
