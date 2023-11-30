// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseActor, IERC20, IERC20Metadata, AngleGovernor, TestStorage } from "./BaseActor.t.sol";
import { console } from "forge-std/console.sol";

contract Voter is BaseActor {
    AngleGovernor internal _angleGovernor;

    constructor(AngleGovernor angleGovernor, IERC20 _agToken, uint256 nbrVoter) BaseActor(nbrVoter, "Voter", _agToken) {
        _angleGovernor = angleGovernor;
    }
}
