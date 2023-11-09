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

import { ILayerZeroEndpoint } from "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";

//solhint-disable
contract AngleGovernorTest is Test {
    event TimelockChange(address oldTimelock, address newTimelock);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

    ProposalSender public proposalSender;
    AngleGovernor public angleGovernor;
    ILayerZeroEndpoint public mainnetLzEndpoint = ILayerZeroEndpoint(0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675);
    IVotes public veANGLE = IVotes(0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5);
    IVotes public veANGLEDelegation;
    TimelockController public mainnetTimelock;
    address public mainnetMultisig = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        veANGLEDelegation = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");

        mainnetTimelock = new TimelockController(1 days, proposers, executors, address(this));
        angleGovernor = new AngleGovernor(veANGLEDelegation, mainnetTimelock);
        mainnetTimelock.grantRole(mainnetTimelock.PROPOSER_ROLE(), address(angleGovernor));
        mainnetTimelock.grantRole(mainnetTimelock.CANCELLER_ROLE(), mainnetMultisig);
        // mainnetTimelock.renounceRole(mainnetTimelock.TIMELOCK_ADMIN_ROLE(), address(this));
        proposalSender = new ProposalSender(mainnetLzEndpoint);
        proposalSender.transferOwnership(address(angleGovernor));
    }

    function test_Initialization() public {
        assertEq(angleGovernor.votingDelay(), 1800);
        assertEq(angleGovernor.votingPeriod(), 36000);
        assertEq(angleGovernor.proposalThreshold(), 100000e18);
        assertEq(angleGovernor.quorumNumerator(), 10);
        assertEq(angleGovernor.timelock(), address(mainnetTimelock));
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

    function test_Clock() public {
        assertEq(angleGovernor.clock(), block.number);
    }
}
