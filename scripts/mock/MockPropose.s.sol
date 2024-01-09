// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import "../../contracts/utils/Errors.sol" as Errors;

contract Propose is Script {
    error WrongCall();

    AngleGovernor angleGovernor = AngleGovernor(payable(0xc8C22F59A931768FAE6B12708F450B4FAB6dd6FE));
    TimelockController timelock = TimelockController(payable(0x64B478B7537395036c65468a6eb9B52FA6096A1f));
    uint256 testerPrivateKey = vm.envUint("TESTER_PRIVATE_KEY");

    function run() external {
        address[] memory target = new address[](1);
        uint256[] memory value = new uint256[](1);
        bytes[] memory callData = new bytes[](1);

        target[0] = 0xc8C22F59A931768FAE6B12708F450B4FAB6dd6FE;
        value[0] = 0;
        callData[0] = hex"0000";

        address[] memory tlTarget = new address[](1);
        uint256[] memory tlValue = new uint256[](1);
        bytes[] memory tlData = new bytes[](1);

        tlTarget[0] = address(timelock);
        tlValue[0] = 0;
        tlData[0] = abi.encodeWithSelector(
            timelock.schedule.selector,
            target[0],
            value[0],
            callData[0],
            bytes32(0),
            1,
            timelock.getMinDelay()
        );

        vm.startBroadcast(testerPrivateKey);

        angleGovernor.propose(tlTarget, tlValue, tlData, "Test proposal");

        vm.stopBroadcast();
    }
}
