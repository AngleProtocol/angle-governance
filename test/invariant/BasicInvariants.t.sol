// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { Voter } from "./actors/Voter.t.sol";
import { Fixture, AngleGovernor } from "../Fixture.t.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract BasicInvariants is Fixture {
    uint256 internal constant _NUM_VOTER = 10;

    Voter internal _voterHandler;
    // Keep track of current proposals
    uint256[] internal _proposals;

    function setUp() public virtual override {
        super.setUp();

        _voterHandler = new Voter(angleGovernor, ANGLE, _NUM_VOTER);

        // Label newly created addresses
        for (uint256 i; i < _NUM_VOTER; i++)
            vm.label(_voterHandler.actors(i), string.concat("Trader ", Strings.toString(i)));

        targetContract(address(_voterHandler));

        {
            bytes4[] memory selectors = new bytes4[](1);
            // selectors[0] = Voter.XXXX.selector;
            // targetSelector(FuzzSelector({ addr: address(_voterHandler), selectors: selectors }));
        }
    }

    function systemState() public view {
        console.log("");
        console.log("SYSTEM STATE");
        console.log("");
        console.log("Calls summary:");
        console.log("-------------------");
        console.log("Voter:swap", _voterHandler.calls("vote"));
        console.log("-------------------");
        console.log("");
    }

    function invariant_XXXXX() public {}
}
