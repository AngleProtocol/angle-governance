// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseActor, IERC20, IERC20Metadata, AngleGovernor, TestStorage } from "./BaseActor.t.sol";
import { console } from "forge-std/console.sol";

contract Voter is BaseActor {
    constructor(AngleGovernor angleGovernor, uint256 nbrVoter) BaseActor(nbrVoter, "Voter", angleGovernor) {}
}
