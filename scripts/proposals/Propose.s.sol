// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import "../Utils.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";

struct Proposal {
    bytes[] calldatas;
    string description;
    address[] targets;
    uint256[] values;
}

contract Propose is Utils {
    using stdJson for string;

    function setUp() public virtual override {}

    function run() external {
        (
            bytes[] memory calldatas,
            string memory description,
            address[] memory targets,
            uint256[] memory values,
            uint256[] memory chainIds
        ) = _deserializeJson();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        AngleGovernor governor = AngleGovernor(payable(0xc8C22F59A931768FAE6B12708F450B4FAB6dd6FE));
        // uint256 proposalId = governor.propose(targets, values, calldatas, description);
        // console.log("Proposal id: %d", proposalId);

        governor.castVoteWithReason(
            69820582563220157920941172467432008974707753288353173612270624136637743015244,
            1,
            "test"
        );
        //
        governor.execute{ value: 345198341313663651 }(targets, values, calldatas, keccak256(bytes(description)));

        vm.stopBroadcast();
    }
}
