// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";

import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { VeANGLEVotingDelegation } from "contracts/VeANGLEVotingDelegation.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Utils.t.sol";

//solhint-disable
contract AngleGovernorTest is Test, Utils {
    event TimelockChange(address oldTimelock, address newTimelock);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event VeANGLEVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);

    ProposalSender public proposalSender;
    AngleGovernor public angleGovernor;
    IVotes public veANGLEDelegation;
    TimelockController public mainnetTimelock;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.roll(block.number + 1152);
        vm.warp(block.timestamp + 10 days);
        veANGLEDelegation = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");

        mainnetTimelock = new TimelockController(1 days, proposers, executors, address(this));
        angleGovernor = new AngleGovernor(
            veANGLEDelegation,
            mainnetTimelock,
            initialVotingDelay,
            initialVotingPeriod,
            initialProposalThreshold,
            initialVoteExtension,
            initialQuorumNumeratorValue,
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
        assertEq(angleGovernor.quorumNumerator(), initialQuorumNumeratorValue);
        assertEq(angleGovernor.lateQuorumVoteExtension(), initialVoteExtension);
        assertEq(angleGovernor.shortCircuitNumerator(), initialShortCircuitNumerator);
        assertEq(angleGovernor.quorumNumerator(), initialQuorumNumeratorValue);
        assertEq(angleGovernor.$votingDelayBlocks(), initialVotingDelayBlocks);
        assertEq(angleGovernor.timelock(), address(mainnetTimelock));
        assertEq(address(angleGovernor.token()), address(veANGLEDelegation));
        assertEq(angleGovernor.CLOCK_MODE(), "mode=timestamp");
        assertEq(angleGovernor.COUNTING_MODE(), "support=bravo&quorum=for,abstain&params=fractional");
    }

    function test_RevertWhen_NotExecutor() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.startPrank(alice);
        TimelockController mainnetTimelock2 = new TimelockController(1 days, proposers, executors, address(this));
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.updateTimelock(mainnetTimelock2);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setVotingDelay(10);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setVotingPeriod(10);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setProposalThreshold(10);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setVeANGLEVotingDelegation(address(veANGLE));
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.updateShortCircuitNumerator(12);
        vm.expectRevert(Errors.NotExecutor.selector);
        angleGovernor.setLateQuorumVoteExtension(12);

        vm.stopPrank();
    }

    function test_UpdateTimelock() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute
        TimelockController mainnetTimelock2 = new TimelockController(1 days, proposers, executors, address(this));

        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit TimelockChange(address(mainnetTimelock), address(mainnetTimelock2));
        hoax(address(mainnetTimelock));
        angleGovernor.updateTimelock(mainnetTimelock2);
        assertEq(angleGovernor.timelock(), address(mainnetTimelock2));
    }

    function test_SetVotingDelay() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit VotingDelaySet(1800, 11);
        hoax(address(mainnetTimelock));
        angleGovernor.setVotingDelay(11);
        assertEq(angleGovernor.votingDelay(), 11);
    }

    function test_SetVotingPeriod() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit VotingPeriodSet(36000, 12);
        hoax(address(mainnetTimelock));
        angleGovernor.setVotingPeriod(12);
        assertEq(angleGovernor.votingPeriod(), 12);
    }

    function test_SetProposalThreshold() public {
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit ProposalThresholdSet(100000e18, 13);
        hoax(address(mainnetTimelock));
        angleGovernor.setProposalThreshold(13);
        assertEq(angleGovernor.proposalThreshold(), 13);
    }

    function test_SetVeANGLEVotingDelegation() public {
        IVotes veANGLEDelegation2 = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation2", "2");
        vm.expectEmit(true, true, true, true, address(angleGovernor));
        emit VeANGLEVotingDelegationSet(address(veANGLEDelegation), address(veANGLEDelegation2));
        hoax(address(mainnetTimelock));
        angleGovernor.setVeANGLEVotingDelegation(address(veANGLEDelegation2));
        assertEq(address(angleGovernor.token()), address(veANGLEDelegation2));
    }

    function test_Clock() public {
        assertEq(angleGovernor.clock(), block.timestamp);
    }

    function test_Propose() public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(1e24)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(15e23)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        _passProposal(1, angleGovernor, address(mainnetTimelock), targets, values, calldatas, description);
    }
}
