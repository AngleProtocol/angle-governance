// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { Delegator } from "./actors/Delegator.t.sol";
import { Param } from "./actors/Param.t.sol";
import { Fixture, AngleGovernor } from "../Fixture.t.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract DelegationInvariants is Fixture {
    uint256 internal constant _NUM_DELEGATORS = 10;
    uint256 internal constant _NUM_PARAMS = 1;

    Delegator internal _delegatorHandler;
    Param internal _paramHandler;

    function setUp() public virtual override {
        super.setUp();

        _delegatorHandler = new Delegator(_NUM_DELEGATORS, ANGLE, address(veANGLE), address(token));
        _paramHandler = new Param(_NUM_PARAMS, ANGLE);

        // Label newly created addresses
        for (uint256 i; i < _NUM_DELEGATORS; i++)
            vm.label(_delegatorHandler.actors(i), string.concat("Delegator ", Strings.toString(i)));
        vm.label({ account: address(_paramHandler), newLabel: "Param" });

        targetContract(address(_delegatorHandler));
        targetContract(address(_paramHandler));

        {
            bytes4[] memory selectors = new bytes4[](5);
            selectors[0] = Delegator.delegate.selector;
            selectors[1] = Delegator.createLock.selector;
            selectors[2] = Delegator.withdraw.selector;
            selectors[3] = Delegator.extendLockTime.selector;
            selectors[4] = Delegator.extendLockAmount.selector;
            targetSelector(FuzzSelector({ addr: address(_delegatorHandler), selectors: selectors }));
        }
        {
            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = Param.wrap.selector;
            targetSelector(FuzzSelector({ addr: address(_paramHandler), selectors: selectors }));
        }
    }

    function invariant_RightNumberOfVotesDelegated() public {
        for (uint256 i; i < _NUM_DELEGATORS; i++) {
            address actor = _delegatorHandler.actors(i);

            assertEq(
                token.delegates(actor),
                _delegatorHandler.delegations(actor),
                "delegatee should be the same as actor"
            );
        }
        for (uint256 i; i < _delegatorHandler.delegateesLength(); i++) {
            address delegatee = _delegatorHandler.delegatees(i);

            address[] memory delegators = _delegatorHandler.reverseDelegationsView(delegatee);
            for (uint256 j; j < delegators.length; j++) {
                address delegator = delegators[j];
                if (veANGLE.locked__end(delegator) > ((block.timestamp / 1 days) * 1 days) + 1 days) {
                    vm.prank(delegator, delegator);
                    token.delegate(delegatee);
                }
            }
            uint256 amount = veANGLE.balanceOf(delegatee);
            for (uint256 j; j < delegators.length; j++) {
                address delegator = delegators[j];
                uint256 balance = veANGLE.balanceOf(delegator);
                amount += balance;
            }
            uint256 votes = token.getVotes(delegatee);
            assertEq(votes, amount, "Delegatee should have votes");
        }
    }

    function invariant_DelegatorsHaveNullVote() public {
        for (uint256 i; i < _NUM_DELEGATORS; i++) {
            address actor = _delegatorHandler.actors(i);
            address delegatee = _delegatorHandler.delegations(actor);
            if (delegatee != address(0) && delegatee != actor)
                assertEq(token.getVotes(actor), 0, "Delegator should have null vote");
        }
    }

    function invariant_CanOnlyDelegateOnceAtATime() public {
        uint256[] memory occurencesDelegator = new uint256[](_NUM_DELEGATORS);
        for (uint256 i; i < _delegatorHandler.delegateesLength(); i++) {
            address delegatee = _delegatorHandler.delegatees(i);
            address[] memory delegators = _delegatorHandler.reverseDelegationsView(delegatee);
            for (uint256 j; j < delegators.length; j++) {
                uint256 index = _delegatorHandler.addressToIndex(delegators[j]);
                occurencesDelegator[index]++;
                assertLe(occurencesDelegator[index], 1, "Delegator should only delegate once at a time");
            }
        }
    }

    function invariant_SumDelegationExternalEqualTotalSupply() public {
        uint256 totalVotes = token.getVotes(alice) +
            token.getVotes(bob) +
            token.getVotes(charlie) +
            token.getVotes(dylan);

        for (uint256 i; i < _NUM_DELEGATORS; i++) {
            address actor = _delegatorHandler.actors(i);
            totalVotes += token.getVotes(actor);
        }
        for (uint256 i; i < _delegatorHandler.delegateesLength(); i++) {
            address delegatee = _delegatorHandler.delegatees(i);
            totalVotes += token.getVotes(delegatee);
        }

        assertEq(
            totalVotes,
            veANGLE.totalSupply(block.timestamp),
            "The sum of voting power should be equal to the totalSupply"
        );
    }

    function invariant_SumDelegationInternalEqualTotalSupply() public {
        uint256 totalVotes = token.getVotes(alice) +
            token.getVotes(bob) +
            token.getVotes(charlie) +
            token.getVotes(dylan);

        for (uint256 i; i < _NUM_DELEGATORS; i++) {
            address actor = _delegatorHandler.actors(i);
            totalVotes += token.getVotes(actor);
            address delegatee = token.delegates(actor);
            totalVotes += token.getVotes(delegatee);
        }

        assertEq(
            totalVotes,
            veANGLE.totalSupply(block.timestamp),
            "The sum of voting power should be equal to the totalSupply"
        );
    }
}
