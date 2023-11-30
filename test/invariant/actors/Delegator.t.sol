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

    mapping(address => uint256) public delegationAmounts;
    mapping(address => address) public delegations;
    mapping(address => address[]) public reverseDelegations;
    mapping(address => Lock) public _locks;
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

    function locks(address locker) public view returns (Lock memory) {
        return _locks[locker];
    }

    function reverseDelegationsView(address locker) public view returns (address[] memory) {
        return reverseDelegations[locker];
    }

    function delegateesLength() public view returns (uint256) {
        return delegatees.length;
    }

    function delegate(uint256 acordIndex, address toDelegate) public useActor(acordIndex) {
        if (toDelegate == address(0)) return;

        uint256 balance = veToken.balanceOf(_currentActor);
        address currentDelegatee = delegations[_currentActor];

        if (balance == 0) {
            return;
        }

        veDelegation.delegate(toDelegate);

        // Update delegations
        delegations[_currentActor] = toDelegate;
        for (uint256 i; i < delegatees.length; i++) {
            if (delegatees[i] == toDelegate) {
                return;
            }
        }
        delegatees.push(toDelegate);
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
    }

    function createLock(uint256 acordIndex, uint256 amount, uint256 duration) public useActor(acordIndex) {
        if (veToken.locked__end(_currentActor) != 0) {
            return;
        }
        duration = bound(duration, 1 weeks, 365 days * 4);
        amount = bound(amount, 100e18, 1_500e18);

        MockANGLE(address(agToken)).mint(_currentActor, amount);
        agToken.approve(address(veToken), amount);

        veToken.create_lock(amount, block.timestamp + duration);

        _locks[_currentActor] = Lock({
            amount: veToken.balanceOf(_currentActor),
            end: veToken.locked__end(_currentActor)
        });
    }

    function withdraw() public {
        if (veToken.locked__end(_currentActor) != 0 && veToken.locked__end(_currentActor) < block.timestamp) {
            veToken.withdraw();

            _locks[_currentActor] = Lock({ amount: 0, end: 0 });
        }
    }

    function extandLockTime(uint256 acordIndex, uint256 duration) public useActor(acordIndex) {
        uint256 end = veToken.locked__end(_currentActor);
        if (end == 0 || end + 1 weeks > block.timestamp + 365 days * 4) {
            return;
        }

        duration = bound(duration, end + 1 weeks, block.timestamp + 365 days * 4);
        veToken.increase_unlock_time(duration);
        _locks[_currentActor].end = veToken.locked__end(_currentActor);
    }

    function extandLockAmount(uint256 acordIndex, uint256 amount) public useActor(acordIndex) {
        if (veToken.balanceOf(_currentActor) == 0) {
            return;
        }
        amount = bound(amount, 100e18, 1_500e18);

        MockANGLE(address(agToken)).mint(_currentActor, amount);
        agToken.approve(address(veToken), amount);
        veToken.increase_amount(amount);

        _locks[_currentActor].amount = veToken.balanceOf(_currentActor);
    }

    function wrap(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, 365 days * 5);
        vm.warp(timestamp);
    }
}
