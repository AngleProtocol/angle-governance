// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { Delegator } from "./actors/Delegator.t.sol";
import { Fixture, AngleGovernor } from "../Fixture.t.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract DelegationInvariants is Fixture {
    uint256 internal constant _NUM_DELEGATORS = 10;

    Delegator internal _delegatorHandler;

    function setUp() public virtual override {
        super.setUp();

        _delegatorHandler = new Delegator(_NUM_DELEGATORS, ANGLE, address(veANGLE), address(token));

        // Label newly created addresses
        for (uint256 i; i < _NUM_DELEGATORS; i++)
            vm.label(_delegatorHandler.actors(i), string.concat("Delegator ", Strings.toString(i)));

        targetContract(address(_delegatorHandler));

        {
            bytes4[] memory selectors = new bytes4[](6);
            selectors[0] = Delegator.delegate.selector;
            selectors[1] = Delegator.createLock.selector;
            selectors[2] = Delegator.extandLockTime.selector;
            selectors[3] = Delegator.extendLockAmount.selector;
            selectors[4] = Delegator.wrap.selector;
            selectors[5] = Delegator.withdraw.selector;
            targetSelector(FuzzSelector({ addr: address(_delegatorHandler), selectors: selectors }));
        }
    }

    function invariant_wow() public {
        for (uint256 i; i < _NUM_DELEGATORS; i++) {
            address actor = _delegatorHandler.actors(i);
            uint256 votes = token.getVotes(actor);

            assertEq(token.delegates(actor), _delegatorHandler.delegations(actor));
            if (_delegatorHandler.delegations(actor) != address(0)) {
                assertEq(votes, 0, "Delegator should not have votes");
            } else {
                Delegator.Lock memory lock = _delegatorHandler.locks(actor);
                if (lock.end > block.timestamp) {
                    assertEq(votes, lock.amount, "Delegator should have votes");
                } else {
                    assertEq(votes, 0, "Delegator should not have votes");
                }
            }
        }
        for (uint256 i; i < _delegatorHandler.delegateesLength(); i++) {
            address delegatee = _delegatorHandler.delegatees(i);
            uint256 votes = token.getVotes(delegatee);

            uint256 amount = 0;
            address[] memory delegators = _delegatorHandler.reverseDelegationsView(delegatee);
            for (uint256 j; j < delegators.length; j++) {
                address delegator = delegators[j];
                Delegator.Lock memory lock = _delegatorHandler.locks(delegator);
                if (lock.end > block.timestamp) amount += lock.amount;
            }
            assertEq(votes, _delegatorHandler.delegationAmounts(delegatee), "Delegatee should have votes");
        }
    }
}
