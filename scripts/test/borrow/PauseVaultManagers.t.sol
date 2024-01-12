// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
/*
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { MockSafe } from "../mock/MockSafe.sol";
import { Utils } from "../Utils.s.sol";
import { ContractType } from "../../scripts/foundry/Constants.s.sol";
import "../../scripts/foundry/Constants.s.sol";

contract PauseVaultManagers is Utils {
    using stdJson for string;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256 chainId = vm.envUint("CHAIN_ID");

        (
            bytes[] memory calldatas,
            string memory description,
            address[] memory targets,
            uint256[] memory values
        ) = _deserializeJson(chainId);

        // Verify that the call will succeed
        MockSafe mockSafe = new MockSafe();
        vm.etch(gnosisSafe, address(mockSafe).code);
        vm.prank(gnosisSafe);
        (bool success, ) = gnosisSafe.call(abi.encode(address(to), payload, operation, 1e6));
        if (!success) revert();
    }
}

*/
