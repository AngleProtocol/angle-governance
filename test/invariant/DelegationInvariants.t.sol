// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { Delegator } from "./actors/Delegator.t.sol";
import { Param } from "./actors/Param.t.sol";
import { Fixture, AngleGovernor } from "../Fixture.t.sol";
import { TimestampStore } from "./stores/TimestampStore.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract DelegationInvariants is Fixture {
    uint256 internal constant _NUM_DELEGATORS = 10;
    uint256 internal constant _NUM_PARAMS = 1;

    Delegator internal _delegatorHandler;
    Param internal _paramHandler;
    TimestampStore internal _timestampStore;

    modifier useCurrentTimestamp() {
        vm.warp(_timestampStore.currentTimestamp());
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        _timestampStore = new TimestampStore();
        _delegatorHandler = new Delegator(_NUM_DELEGATORS, ANGLE, address(veANGLE), address(token), _timestampStore);
        _paramHandler = new Param(_NUM_PARAMS, ANGLE, _timestampStore);

        // Label newly created addresses
        for (uint256 i; i < _NUM_DELEGATORS; i++)
            vm.label(_delegatorHandler.actors(i), string.concat("Delegator ", Strings.toString(i)));
        vm.label({ account: address(_timestampStore), newLabel: "TimestampStore" });
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

    function invariant_RightNumberOfVotesDelegated() public useCurrentTimestamp {
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
            uint256 votes = token.getVotes(delegatee);

            uint256 amount = 0;
            address[] memory delegators = _delegatorHandler.reverseDelegationsView(delegatee);
            for (uint256 j; j < delegators.length; j++) {
                address delegator = delegators[j];
                uint256 balance = veANGLE.balanceOf(delegator);
                amount += balance;
            }
            assertEq(votes, amount, "Delegatee should have votes");
        }
    }
}
