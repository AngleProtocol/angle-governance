// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import { IveANGLEVotingDelegation } from "contracts/interfaces/IveANGLEVotingDelegation.sol";
import { deployMockANGLE, deployVeANGLE } from "../scripts/test/DeployANGLE.s.sol";
import { ERC20 } from "oz-v5/token/ERC20/ERC20.sol";
import "contracts/interfaces/IveANGLE.sol";
import "./external/VyperDeployer.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { VeANGLEVotingDelegation, ECDSA } from "contracts/VeANGLEVotingDelegation.sol";
import { TimelockControllerWithCounter, TimelockController } from "contracts/TimelockControllerWithCounter.sol";
import "contracts/utils/Errors.sol" as Errors;
import "./Constants.t.sol";
import "./Utils.t.sol";

import { Test, stdError } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract Fixture is Test {
    uint256 public constant FORK_BLOCK_NUMBER = 1152;
    uint256 public constant FORK_BLOCK_TIMSESTAMP = 365 days + 111 days;
    uint256 public constant GOVERNOR_INIT_BALANCE = 300_000_000 * 1e18;

    address public alice;
    address public bob;
    address public charlie;
    address public dylan;
    address public sweeper;

    VyperDeployer public vyperDeployer;

    ERC20 public ANGLE;
    IveANGLE public veANGLE;
    ProposalSender public proposalSender;
    AngleGovernor public angleGovernor;
    AngleGovernor public receiver;
    VeANGLEVotingDelegation public token;
    TimelockControllerWithCounter public mainnetTimelock;

    function setUp() public virtual {
        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        dylan = vm.addr(4);
        sweeper = address(uint160(uint256(keccak256(abi.encodePacked("sweeper")))));

        vm.label(mainnetMultisig, "mainnetMultisig");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dylan, "Dylan");
        vm.label(sweeper, "Sweeper");

        vm.roll(block.number + FORK_BLOCK_NUMBER);

        vm.warp(block.timestamp + FORK_BLOCK_TIMSESTAMP);

        // Deploy necessary contracts - for governance to be deployed
        vyperDeployer = new VyperDeployer();
        (address _mockANGLE, , ) = deployMockANGLE();
        ANGLE = ERC20(_mockANGLE);
        deal(address(ANGLE), mainnetMultisig, GOVERNOR_INIT_BALANCE);
        (address _mockVeANGLE, , ) = deployVeANGLE(vyperDeployer, _mockANGLE, mainnetMultisig);
        veANGLE = IveANGLE(_mockVeANGLE);
        _setupDealAndLockANGLE(alice, 1_000_000 * 1e18, 365 days);
        _setupDealAndLockANGLE(bob, 333_000 * 1e18, 4 * 365 days);
        _setupDealAndLockANGLE(charlie, 500_000 * 1e18, 571 days);
        _setupDealAndLockANGLE(dylan, 2000 * 1e18, 10 days);

        // Deploy governance
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        token = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");
        mainnetTimelock = new TimelockControllerWithCounter(1 days, proposers, executors, address(this));
        angleGovernor = new AngleGovernor(
            token,
            address(mainnetTimelock),
            initialVotingDelay,
            initialVotingPeriod,
            initialProposalThreshold,
            initialVoteExtension,
            initialQuorumNumerator,
            initialShortCircuitNumerator,
            initialVotingDelayBlocks
        );
        receiver = angleGovernor;
        mainnetTimelock.grantRole(mainnetTimelock.PROPOSER_ROLE(), address(angleGovernor));
        mainnetTimelock.grantRole(mainnetTimelock.CANCELLER_ROLE(), mainnetMultisig);
        proposalSender = new ProposalSender(mainnetLzEndpoint);
        proposalSender.transferOwnership(address(angleGovernor));

        vm.label(address(mainnetTimelock), "Timelock");
        vm.label(address(angleGovernor), "AngleGovernor");
        vm.label(address(ANGLE), "ANGLE");
        vm.label(address(veANGLE), "veANGLE");
        vm.label(address(token), "veANGLE Delegation");
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _setupDealAndLockANGLE(address account, uint256 amount, uint256 lockTime) internal {
        // Give ANGLE balances
        deal(address(ANGLE), account, amount);
        assertEq(ANGLE.balanceOf(account), amount, "account gets ANGLE");

        // even distribution of lock time / veANGLE balance
        lockTime = bound(lockTime, 1, (365 days * 4));
        vm.startPrank(account, account);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + lockTime);
        vm.stopPrank();
        assertGt(veANGLE.balanceOf(account), 0, "veANGLE for an account is always greater than 0");
    }

    function dealCreateLockANGLE(address account, uint256 amount) public {
        hoax(mainnetMultisig);
        ANGLE.transfer(account, amount);

        vm.startPrank(account, account);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();
    }
}
