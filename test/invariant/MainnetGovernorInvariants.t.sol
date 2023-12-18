// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "oz/token/ERC20/extensions/IERC20Metadata.sol";
import "oz/utils/Strings.sol";
import {Voter} from "./actors/Voter.t.sol";
import {Proposer} from "./actors/Proposer.t.sol";
import {BadVoter} from "./actors/BadVoter.t.sol";
import {Fixture, AngleGovernor} from "../Fixture.t.sol";
import {ProposalStore} from "./stores/ProposalStore.sol";

//solhint-disable
import {console} from "forge-std/console.sol";

contract MainnetGovernorInvariants is Fixture {
    uint256 internal constant _NUM_VOTER = 10;

    Voter internal _voterHandler;
    Proposer internal _proposerHandler;
    BadVoter internal _badVoterHandler;

    // Keep track of current proposals
    ProposalStore internal _proposalStore;

    function setUp() public virtual override {
        super.setUp();

        _proposalStore = new ProposalStore();
        _voterHandler = new Voter(angleGovernor, ANGLE, _NUM_VOTER, _proposalStore);
        _proposerHandler = new Proposer(angleGovernor, ANGLE, 1, _proposalStore, token);
        _badVoterHandler = new BadVoter(angleGovernor, ANGLE, _NUM_VOTER, _proposalStore);

        // Label newly created addresses
        vm.label({account: address(_proposalStore), newLabel: "ProposalStore"});
        for (uint256 i; i < _NUM_VOTER; i++) {
            vm.label(_voterHandler.actors(i), string.concat("Voter ", Strings.toString(i)));
            _setupDealAndLockANGLE(_voterHandler.actors(i), 100000000e18, 4 * 365 days);
        }
        for (uint256 i; i < _NUM_VOTER; i++) {
            vm.label(_badVoterHandler.actors(i), string.concat("BadVoter ", Strings.toString(i)));
            _setupDealAndLockANGLE(_badVoterHandler.actors(i), 100000000e18, 4 * 365 days);
        }
        vm.label(_proposerHandler.actors(0), "Proposer");
        _setupDealAndLockANGLE(_proposerHandler.actors(0), angleGovernor.proposalThreshold() * 10, 4 * 365 days);

        vm.warp(block.timestamp + 1 weeks);

        targetContract(address(_voterHandler));
        targetContract(address(_proposerHandler));
        targetContract(address(_badVoterHandler));

        {
            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = Voter.vote.selector;
            targetSelector(FuzzSelector({addr: address(_voterHandler), selectors: selectors}));
        }
        {
            bytes4[] memory selectors = new bytes4[](4);
            selectors[0] = Proposer.propose.selector;
            selectors[1] = Proposer.execute.selector;
            selectors[2] = Proposer.skipVotingDelay.selector;
            selectors[3] = Proposer.shortCircuit.selector;
            targetSelector(FuzzSelector({addr: address(_proposerHandler), selectors: selectors}));
        }
        {
            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = BadVoter.vote.selector;
            targetSelector(FuzzSelector({addr: address(_badVoterHandler), selectors: selectors}));
        }
    }

    function invariant_MainnetGovernorSuccess() public {}
}
