// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./BaseActor.t.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";
import { MockANGLE } from "../../external/MockANGLE.sol";
import "contracts/interfaces/IveANGLE.sol";
import "contracts/utils/Errors.sol";
import { console } from "forge-std/console.sol";

contract Delegator is BaseActor {
    IveANGLE public veToken;
    IERC5805 public veDelegation;

    struct Lock {
        uint256 amount;
        uint256 end;
    }

    mapping(address => address) public delegations;
    mapping(address => address[]) public reverseDelegations;
    address[] public delegatees;

    constructor(
        uint256 _nbrActor,
        IERC20 _agToken,
        address _veToken,
        address _veDelegation
    ) BaseActor(_nbrActor, "Delegator", _agToken) {
        veToken = IveANGLE(_veToken);
        veDelegation = IERC5805(_veDelegation);
    }

    function reverseDelegationsView(address locker) public view returns (address[] memory) {
        return reverseDelegations[locker];
    }

    function delegateesLength() public view returns (uint256) {
        return delegatees.length;
    }

    function delegate(uint256 actorIndex, address toDelegate) public useActor(actorIndex) {
        if (toDelegate == address(0)) return;

        uint256 balance = veToken.balanceOf(_currentActor);
        address currentDelegatee = delegations[_currentActor];

        if (balance == 0) {
            return;
        }

        veDelegation.delegate(toDelegate);
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);

        // Update delegations
        if (toDelegate == currentDelegatee) {
            return;
        }
        string memory path = "/root/angle/angle-governance/output.txt";

        string memory line1 = string.concat(
            "Delegator ",
            vm.toString(_currentActor),
            " delegated ",
            vm.toString(balance),
            " to ",
            vm.toString(toDelegate)
        );
        vm.writeLine(path, line1);
        reverseDelegations[toDelegate].push(_currentActor);
        for (uint256 i; i < reverseDelegations[currentDelegatee].length; i++) {
            if (reverseDelegations[currentDelegatee][i] == _currentActor) {
                reverseDelegations[currentDelegatee][i] = reverseDelegations[currentDelegatee][
                    reverseDelegations[currentDelegatee].length - 1
                ];
                reverseDelegations[currentDelegatee].pop();
                break;
            }
        }
        delegations[_currentActor] = toDelegate;
        for (uint256 i; i < delegatees.length; i++) {
            if (delegatees[i] == toDelegate) {
                return;
            }
        }
        delegatees.push(toDelegate);

        string memory line2 = string.concat("Finished delegating ");
        vm.writeLine(path, line2);
    }

    function createLock(uint256 actorIndex, uint256 amount, uint256 duration) public useActor(actorIndex) {
        if (veToken.locked__end(_currentActor) != 0) {
            return;
        }
        duration = bound(duration, 1 weeks, 365 days * 4);
        amount = bound(amount, 100e18, 1_500e18);

        MockANGLE(address(angle)).mint(_currentActor, amount);
        angle.approve(address(veToken), amount);

        veToken.create_lock(amount, block.timestamp + duration);

        string memory path = "/root/angle/angle-governance/output.txt";

        string memory line1 = string.concat(
            "Actor ",
            vm.toString(_currentActor),
            " locked ",
            vm.toString(amount),
            " for ",
            vm.toString(duration)
        );
        vm.writeLine(path, line1);
    }

    function withdraw() public {
        if (veToken.locked__end(_currentActor) != 0 && veToken.locked__end(_currentActor) < block.timestamp) {
            veToken.withdraw();
        }
    }

    function extendLockTime(uint256 actorIndex, uint256 duration) public useActor(actorIndex) {
        uint256 end = veToken.locked__end(_currentActor);
        if (end == 0 || end + 1 weeks > block.timestamp + 365 days * 4) {
            return;
        }

        duration = bound(duration, end + 1 weeks, block.timestamp + 365 days * 4);
        veToken.increase_unlock_time(duration);
    }

    function extendLockAmount(uint256 actorIndex, uint256 amount) public useActor(actorIndex) {
        if (veToken.balanceOf(_currentActor) == 0) {
            return;
        }
        amount = bound(amount, 100e18, 1_500e18);

        MockANGLE(address(angle)).mint(_currentActor, amount);
        angle.approve(address(veToken), amount);
        veToken.increase_amount(amount);
    }

    function wrap(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, 365 days * 5);
        vm.warp(timestamp);
    }
}
