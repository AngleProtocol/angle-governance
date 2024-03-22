// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz-v5/governance/IGovernor.sol";
import { IVotes } from "oz-v5/governance/extensions/GovernorVotes.sol";
import { GovernorCountingSimple } from "oz-v5/governance/extensions/GovernorCountingSimple.sol";
import { Strings } from "oz-v5/utils/Strings.sol";
import { ERC20 } from "oz-v5/token/ERC20/ERC20.sol";

import { stdStorage, StdStorage, Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { deployMockANGLE, MockANGLE } from "../../scripts/test/DeployANGLE.s.sol";
import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { VeANGLEVotingDelegation } from "contracts/VeANGLEVotingDelegation.sol";
import { TimelockControllerWithCounter, TimelockController } from "contracts/TimelockControllerWithCounter.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Utils.t.sol";

//solhint-disable
contract GovernorShortCircuitTest is Test, Utils {
    using stdStorage for StdStorage;

    event ShortCircuitNumeratorUpdated(uint256 oldShortCircuitThreshold, uint256 newShortCircuitThreshold);

    ProposalSender public proposalSender;
    AngleGovernor public angleGovernor;
    MockANGLE public ANGLE;
    IVotes public veANGLEDelegation;
    TimelockControllerWithCounter public mainnetTimelock;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);
    address public proposer = vm.addr(uint256(keccak256("proposer")));
    address public allMighty = vm.addr(uint256(keccak256("allMighty")));

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.roll(block.number + 1152);
        vm.warp(block.timestamp + 10 days);
        (address _mockANGLE, , ) = deployMockANGLE();
        ANGLE = MockANGLE(_mockANGLE);
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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _votePassingQuorum(uint256 proposalId) public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(allMighty)),
            abi.encode(angleGovernor.shortCircuitThreshold(angleGovernor.proposalSnapshot(proposalId)) + 1)
        );
        hoax(allMighty);
        angleGovernor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
    }

    function _voteDefeatQuorum(uint256 proposalId) public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(allMighty)),
            abi.encode(angleGovernor.shortCircuitThreshold(angleGovernor.proposalSnapshot(proposalId)) + 1)
        );
        hoax(allMighty);
        angleGovernor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Against));
    }

    function _proposeTx(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public returns (uint256 pid) {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastVotes.selector, address(proposer)),
            abi.encode(angleGovernor.proposalThreshold())
        );
        hoax(proposer);
        pid = angleGovernor.propose(targets, values, calldatas, "");
    }

    function _testSetShortCircuitThreshold(uint256 newShortCircuit) internal {
        uint256 shortCircuitThreshold = angleGovernor.shortCircuitNumerator();

        assertEq(angleGovernor.shortCircuitNumerator(), shortCircuitThreshold, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(angleGovernor);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateShortCircuitNumerator.selector, newShortCircuit);

        uint256 pid = _proposeTx(targets, values, calldatas);

        mineBlocksBySecond(angleGovernor.votingDelay() + 1);
        vm.roll(block.number + 1);

        _votePassingQuorum(pid);

        mineBlocksBySecond(angleGovernor.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(angleGovernor.state(pid)),
            "Proposal state is succeeded"
        );

        stdstore.target(address(angleGovernor)).sig("timelock()").checked_write(address(angleGovernor));
        vm.expectEmit(true, true, true, true);
        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitThreshold: shortCircuitThreshold,
            newShortCircuitThreshold: newShortCircuit
        });
        angleGovernor.execute(targets, values, calldatas, keccak256(bytes("")));
        stdstore.target(address(angleGovernor)).sig("timelock()").checked_write(address(mainnetTimelock));

        assertEq(angleGovernor.shortCircuitNumerator(), newShortCircuit, "value changed");
        assertEq(
            angleGovernor.shortCircuitNumerator(block.timestamp - 1),
            shortCircuitThreshold,
            "old value preserved for old timestamps"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         TESTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Test the revert case for shortCircuitThreshold() where there is no proposal at the provided timestamp
    function test_ShortCircuitInvalidTimepoint() public {
        vm.expectRevert(Errors.InvalidTimepoint.selector);
        angleGovernor.shortCircuitThreshold(block.timestamp);

        vm.expectRevert(Errors.InvalidTimepoint.selector);
        angleGovernor.shortCircuitThreshold(block.timestamp);
    }

    // Short circuit success works
    function test_ProposeEarlySuccess() public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(1e25)
        );

        _testSetShortCircuitThreshold(10); // Set short circuit lower for the purpose of this test

        uint256 amount = 100e18;
        // put 100 ANGLE in mainnetTimelock to transfer later in proposal
        ANGLE.mint(address(angleGovernor), amount);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(ANGLE);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, amount);

        uint256 pid = _proposeTx(targets, values, calldatas);

        mineBlocksBySecond(angleGovernor.votingDelay() + 1);
        vm.roll(block.number + 1);

        _votePassingQuorum(pid);

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(angleGovernor.state(pid)),
            "Proposal state is succeeded"
        );

        // majorityFor allows skipping delay but still timelock
        angleGovernor.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(ANGLE.balanceOf(bob), amount, "Bob received ANGLE");
        assertEq(ANGLE.balanceOf(address(angleGovernor)), 0, "angleGovernor has no ANGLE");
        assertEq(
            uint256(IGovernor.ProposalState.Executed),
            uint256(angleGovernor.state(pid)),
            "Proposal state is executed"
        );
    }

    // Short circuit success works on Alpha
    function test_ProposeEarlyDefeat() public {
        vm.mockCall(
            address(veANGLEDelegation),
            abi.encodeWithSelector(veANGLEDelegation.getPastTotalSupply.selector),
            abi.encode(1e25)
        );

        _testSetShortCircuitThreshold(10); // Set short circuit lower for the purpose of this test

        uint256 amount = 100e18;
        // put 100 ANGLE in mainnetTimelock to transfer later in proposal
        ANGLE.mint(address(angleGovernor), amount);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(ANGLE);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, amount);

        uint256 pid = _proposeTx(targets, values, calldatas);

        mineBlocksBySecond(angleGovernor.votingDelay() + 1);
        vm.roll(block.number + 1);

        _voteDefeatQuorum(pid);

        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(angleGovernor.state(pid)),
            "Proposal state is defeated"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                pid,
                IGovernor.ProposalState.Defeated,
                bytes32(0x0000000000000000000000000000000000000000000000000000000000000030)
            )
        );
        angleGovernor.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(ANGLE.balanceOf(bob), 0, "Bob didn't received ANGLE");
        assertEq(ANGLE.balanceOf(address(angleGovernor)), amount, "mainnetTimelock has no ANGLE");
    }
}
