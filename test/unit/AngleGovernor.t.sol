// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz-v5/governance/IGovernor.sol";
import { IVotes } from "oz-v5/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz-v5/utils/Strings.sol";

import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { VeANGLEVotingDelegation } from "contracts/VeANGLEVotingDelegation.sol";
import { TimelockControllerWithCounter, TimelockController } from "contracts/TimelockControllerWithCounter.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Utils.t.sol";

//solhint-disable
contract AngleGovernorTest is Test, Utils {
    event TimelockChange(address oldTimelock, address newTimelock);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event VeANGLEVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);
    event ShortCircuitNumeratorUpdated(uint256 oldShortCircuitNumerator, uint256 newShortCircuitNumerator);
    event VotingDelayBlocksSet(uint256 oldVotingDelayBlocks, uint256 newVotingDelayBlocks);
    event LateQuorumVoteExtensionSet(uint64 oldVoteExtension, uint64 newVoteExtension);

    ProposalSender public proposalSender;
    AngleGovernor public angleGovernor;
    IVotes public veANGLEDelegation;
    TimelockControllerWithCounter public mainnetTimelock;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.roll(block.number + 1152);
        vm.warp(block.timestamp + 10 days);
        veANGLEDelegation = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");

        mainnetTimelock = new TimelockControllerWithCounter(1 days, proposers, executors, address(this));
        angleGovernor = new AngleGovernor(
            veANGLEDelegation,
            address(mainnetTimelock),
            initialVotingDelay,
            initialVotingPeriod,
            initialProposalThreshold,
            initialVoteExtension,
            initialQuorumNumerator,
            initialShortCircuitNumerator,
            initialVotingDelayBlocks
        );
        mainnetTimelock.grantRole(mainnetTimelock.PROPOSER_ROLE(), address(angleGovernor));
        mainnetTimelock.grantRole(mainnetTimelock.CANCELLER_ROLE(), mainnetMultisig);
        // mainnetTimelock.renounceRole(mainnetTimelock.TIMELOCK_ADMIN_ROLE(), address(this));
        proposalSender = new ProposalSender(mainnetLzEndpoint);
        proposalSender.transferOwnership(address(angleGovernor));
    }

    function test_Initialization() public {
        assertEq(angleGovernor.votingDelay(), initialVotingDelay);
        assertEq(angleGovernor.votingPeriod(), initialVotingPeriod);
        assertEq(angleGovernor.proposalThreshold(), initialProposalThreshold);
        assertEq(angleGovernor.quorumNumerator(), initialQuorumNumerator);
        assertEq(angleGovernor.lateQuorumVoteExtension(), initialVoteExtension);
        assertEq(angleGovernor.shortCircuitNumerator(), initialShortCircuitNumerator);
        assertEq(angleGovernor.$votingDelayBlocks(), initialVotingDelayBlocks);
        assertEq(address(angleGovernor.timelock()), address(mainnetTimelock));
        assertEq(address(angleGovernor.token()), address(veANGLEDelegation));
        assertEq(angleGovernor.CLOCK_MODE(), "mode=timestamp");
        assertEq(angleGovernor.COUNTING_MODE(), "support=bravo&quorum=for,abstain&params=fractional");
        assertEq(angleGovernor.CLOCK_MODE(), VeANGLEVotingDelegation(address(veANGLEDelegation)).CLOCK_MODE());
    }

    function test_RevertWhen_NotExecutor() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.startPrank(alice);
        TimelockControllerWithCounter mainnetTimelock2 = new TimelockControllerWithCounter(
            1 days,
            proposers,
            executors,
            address(this)
        );
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.updateTimelock(address(mainnetTimelock2));
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setVotingDelay(10);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setVotingDelayBlocks(100);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setVotingPeriod(10);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setProposalThreshold(10);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.updateShortCircuitNumerator(12);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setLateQuorumVoteExtension(12);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.updateQuorumNumerator(12);

        vm.stopPrank();
    }

    function test_UpdateTimelock() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute
        TimelockControllerWithCounter mainnetTimelock2 = new TimelockControllerWithCounter(
            1 days,
            proposers,
            executors,
            address(this)
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        hoax(address(mainnetTimelock));
        angleGovernor.updateTimelock(address(0));

        hoax(address(mainnetTimelock));
        angleGovernor.updateTimelock(address(mainnetTimelock2));
        assertEq(address(angleGovernor.timelock()), address(mainnetTimelock2));
    }

    function test_SetVotingDelay() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit VotingDelaySet(initialVotingDelay, 11);
        hoax(address(mainnetTimelock));
        angleGovernor.setVotingDelay(11);
        assertEq(angleGovernor.votingDelay(), 11);
    }

    function test_SetVotingDelayBlocks() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit VotingDelayBlocksSet(initialVotingDelayBlocks, 100);
        hoax(address(mainnetTimelock));
        angleGovernor.setVotingDelayBlocks(100);
        assertEq(angleGovernor.$votingDelayBlocks(), 100);
    }

    function test_SetVotingPeriod() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit VotingPeriodSet(initialVotingPeriod, 12);
        hoax(address(mainnetTimelock));
        angleGovernor.setVotingPeriod(12);
        assertEq(angleGovernor.votingPeriod(), 12);
    }

    function test_SetProposalThreshold() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit ProposalThresholdSet(initialProposalThreshold, 13);
        hoax(address(mainnetTimelock));
        angleGovernor.setProposalThreshold(13);
        assertEq(angleGovernor.proposalThreshold(), 13);
    }

    function test_UpdateQuorumNumerator() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit QuorumNumeratorUpdated(initialQuorumNumerator, 13);
        hoax(address(mainnetTimelock));
        angleGovernor.updateQuorumNumerator(13);
        assertEq(angleGovernor.quorumNumerator(), 13);
    }

    function test_RevertWhen_UpdateShortCircuitNumeratorLargerDenominator() public {
        vm.expectRevert(Errors.ShortCircuitNumeratorGreaterThanQuorumDenominator.selector);
        hoax(address(mainnetTimelock));
        angleGovernor.updateShortCircuitNumerator(101);
    }

    function test_UpdateShortCircuitNumerator() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit ShortCircuitNumeratorUpdated(initialShortCircuitNumerator, 60);
        hoax(address(mainnetTimelock));
        angleGovernor.updateShortCircuitNumerator(60);
        assertEq(angleGovernor.shortCircuitNumerator(), 60);
    }

    function test_SetLateQuorumVoteExtension() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit LateQuorumVoteExtensionSet(initialVoteExtension, 1800);
        hoax(address(mainnetTimelock));
        angleGovernor.setLateQuorumVoteExtension(1800);
        assertEq(angleGovernor.lateQuorumVoteExtension(), 1800);
    }

    function test_Clock() public {
        assertEq(angleGovernor.clock(), block.timestamp);
        assertEq(angleGovernor.clock(), VeANGLEVotingDelegation(address(veANGLEDelegation)).clock());
    }
}
