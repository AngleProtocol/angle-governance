// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "utils/script/LibUtils.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract CrossChainProposal is LibUtils {
    function run() external {
        console.log(_chainToContract(CHAIN_GNOSIS, ContractType.Governor));
    }
}
