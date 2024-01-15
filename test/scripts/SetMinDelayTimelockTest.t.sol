// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "./ScriptHelpers.t.sol";
import "../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract SetMinDelayTimelockTest is ScriptHelpers {
    using stdJson for string;

    uint256 constant newMinDelay = uint256(1 weeks);

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        // TODO remove when on chain tx are passed to connect chains
        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);
        ProposalSender proposalSender = ProposalSender(
            payable(_chainToContract(CHAIN_SOURCE, ContractType.ProposalSender))
        );
        uint256[] memory ALL_CHAINS = new uint256[](10);
        ALL_CHAINS[0] = CHAIN_LINEA;
        ALL_CHAINS[1] = CHAIN_POLYGON;
        ALL_CHAINS[2] = CHAIN_ARBITRUM;
        ALL_CHAINS[3] = CHAIN_AVALANCHE;
        ALL_CHAINS[4] = CHAIN_OPTIMISM;
        ALL_CHAINS[5] = CHAIN_GNOSIS;
        ALL_CHAINS[6] = CHAIN_BNB;
        ALL_CHAINS[7] = CHAIN_CELO;
        ALL_CHAINS[8] = CHAIN_POLYGONZKEVM;
        ALL_CHAINS[9] = CHAIN_BASE;

        vm.startPrank(_chainToContract(CHAIN_SOURCE, ContractType.Governor));
        for (uint256 i; i < ALL_CHAINS.length; i++) {
            uint256 chainId = ALL_CHAINS[i];
            proposalSender.setTrustedRemoteAddress(
                getLZChainId(chainId),
                abi.encodePacked(_chainToContract(chainId, ContractType.ProposalReceiver))
            );
        }
        vm.stopPrank();

        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
                payable(_chainToContract(chainId, ContractType.Timelock))
            );
            vm.selectFork(forkIdentifier[chainId]);
            uint256 minDelay = timelock.getMinDelay();
            assertEq(minDelay, newMinDelay);
        }
    }
}
