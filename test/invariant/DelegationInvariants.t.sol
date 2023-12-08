// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import { Delegator } from "./actors/Delegator.t.sol";
import { Fixture, AngleGovernor } from "../Fixture.t.sol";
import { TimestampStore } from "./stores/TimestampStore.sol";

//solhint-disable
import { console } from "forge-std/console.sol";

contract DelegationInvariants is Fixture {
    uint256 internal constant _NUM_DELEGATORS = 10;

    Delegator internal _delegatorHandler;
    TimestampStore internal _timestampStore;

    modifier useCurrentTimestamp() {
        vm.warp(_timestampStore.currentTimestamp());
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        _timestampStore = new TimestampStore();
        _delegatorHandler = new Delegator(_NUM_DELEGATORS, ANGLE, address(veANGLE), address(token), _timestampStore);

        // Label newly created addresses
        for (uint256 i; i < _NUM_DELEGATORS; i++)
            vm.label(_delegatorHandler.actors(i), string.concat("Delegator ", Strings.toString(i)));
        vm.label({ account: address(_timestampStore), newLabel: "TimestampStore" });

        targetContract(address(_delegatorHandler));

        {
            bytes4[] memory selectors = new bytes4[](4);
            selectors[0] = Delegator.delegate.selector;
            selectors[1] = Delegator.createLock.selector;
            // selectors[2] = Delegator.extendLockTime.selector;
            // selectors[3] = Delegator.extendLockAmount.selector;
            selectors[2] = Delegator.wrap.selector;
            selectors[3] = Delegator.withdraw.selector;
            targetSelector(FuzzSelector({ addr: address(_delegatorHandler), selectors: selectors }));
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
            string memory path = "/root/angle/angle-governance/output.txt";

            string memory line1 = string.concat(
                "Delegatee should have votes: ",
                Strings.toString(votes),
                " ",
                Strings.toString(amount),
                " ",
                vm.toString(delegatee)
            );
            vm.writeLine(path, line1);
            assertEq(votes, amount, "Delegatee should have votes");
        }
    }
}
