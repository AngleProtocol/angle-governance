// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";

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
contract GovernorStateAndProposeTest is Test, Utils {
    event TimelockChange(address oldTimelock, address newTimelock);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event VeANGLEVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);

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

    function test_RevertWhen_GovernorInsufficientProposerVotes(uint256 votes) public {
        votes = bound(votes, 0, angleGovernor.proposalThreshold() - 1);
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(votes)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector,
                whale,
                votes,
                angleGovernor.proposalThreshold()
            )
        );
        hoax(whale);
        uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);
    }

    function test_RevertWhen_GovernorInvalidProposalLength(uint256 votes) public {
        votes = bound(votes, angleGovernor.proposalThreshold(), type(uint256).max);
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(votes)
        );

        {
            address[] memory targets = new address[](0);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](1);
            string memory description = "Updating Quorum";

            values[0] = 0;
            calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorInvalidProposalLength.selector,
                    targets.length,
                    calldatas.length,
                    values.length
                )
            );
            hoax(whale);
            uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);
        }

        {
            address[] memory targets = new address[](0);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](0);
            string memory description = "Updating Quorum";

            values[0] = 0;

            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorInvalidProposalLength.selector,
                    targets.length,
                    calldatas.length,
                    values.length
                )
            );
            hoax(whale);
            uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);
        }

        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](1);
            string memory description = "Updating Quorum";

            targets[0] = address(angleGovernor);
            targets[1] = address(angleGovernor);
            values[0] = 0;
            calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorInvalidProposalLength.selector,
                    targets.length,
                    calldatas.length,
                    values.length
                )
            );
            hoax(whale);
            uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);
        }
    }

    function test_RevertWhen_GovernorUnexpectedProposalState_Succeeded() public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(1e24)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(1e25)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);

        // revert because in pending state
        {
            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Pending,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }

        // revert because in active state
        {
            vm.warp(block.timestamp + angleGovernor.votingDelay() + 1);
            vm.roll(block.number + angleGovernor.$votingDelayBlocks() + 1);
            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Active,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }

        // revert because in successful state
        {
            hoax(whale);
            angleGovernor.castVote(proposalId, 1);
            vm.warp(block.timestamp + angleGovernor.votingPeriod() + 1);

            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Succeeded,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }
    }

    function test_RevertWhen_GovernorUnexpectedProposalState_Defeated() public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(1e24)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(1e25)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);

        // revert because in defeated state
        {
            vm.warp(block.timestamp + angleGovernor.votingDelay() + 1);
            vm.roll(block.number + angleGovernor.$votingDelayBlocks() + 1);

            hoax(whale);
            angleGovernor.castVote(proposalId, 0);
            vm.warp(block.timestamp + angleGovernor.votingPeriod() + 1);

            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Defeated,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }
    }

    function test_RevertWhen_GovernorUnexpectedProposalState_ShortCircuitSucceeded(uint256 votes) public {
        votes = bound(
            votes,
            (totalVotes * angleGovernor.shortCircuitNumerator()) / angleGovernor.quorumDenominator() + 1,
            totalVotes
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(votes)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(totalVotes)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);

        // revert because in succeeded state
        {
            vm.warp(block.timestamp + angleGovernor.votingDelay() + 1);
            vm.roll(block.number + angleGovernor.$votingDelayBlocks() + 1);

            hoax(whale);
            angleGovernor.castVote(proposalId, 1);

            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Succeeded,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }
    }

    function test_RevertWhen_GovernorUnexpectedProposalState_ShortCircuitDefeated(uint256 votes) public {
        votes = bound(
            votes,
            (totalVotes * angleGovernor.shortCircuitNumerator()) / angleGovernor.quorumDenominator() + 1,
            totalVotes
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(votes)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(totalVotes)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);

        // revert because in defeated state
        {
            vm.warp(block.timestamp + angleGovernor.votingDelay() + 1);
            vm.roll(block.number + angleGovernor.$votingDelayBlocks() + 1);

            hoax(whale);
            angleGovernor.castVote(proposalId, 0);

            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Defeated,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }
    }

    function test_RevertWhen_GovernorUnexpectedProposalState_Executed(uint256 votes) public {
        votes = bound(
            votes,
            (totalVotes * angleGovernor.shortCircuitNumerator()) / angleGovernor.quorumDenominator() + 1,
            totalVotes
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(votes)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(totalVotes)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        uint256 proposalId = _passProposal(angleGovernor, targets, values, calldatas, description);

        // revert because in Executed state
        {
            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Executed,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }
    }

    function test_RevertWhen_GovernorUnexpectedProposalState_Canceled() public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(whale)),
            abi.encode(totalVotes / 20)
        );
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(totalVotes)
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Updating Quorum";

        targets[0] = address(angleGovernor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorumNumerator.selector, 11);

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(targets, values, calldatas, description);

        // revert because in canceled state
        {
            hoax(whale);
            angleGovernor.cancel(targets, values, calldatas, keccak256(bytes(description)));

            assertEq(uint256(angleGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    proposalId,
                    IGovernor.ProposalState.Canceled,
                    bytes32(0)
                )
            );
            hoax(whale);
            angleGovernor.propose(targets, values, calldatas, description);
        }
    }
}
