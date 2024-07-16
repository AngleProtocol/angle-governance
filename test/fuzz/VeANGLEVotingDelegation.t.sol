// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { IveANGLEVotingDelegation } from "contracts/interfaces/IveANGLEVotingDelegation.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { deployMockANGLE, deployVeANGLE } from "../../scripts/test/DeployANGLE.s.sol";
import { ERC20 } from "oz-v5/token/ERC20/ERC20.sol";
import "contracts/interfaces/IveANGLE.sol";
import "../external/VyperDeployer.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { VeANGLEVotingDelegation, ECDSA } from "contracts/VeANGLEVotingDelegation.sol";
import { TimelockControllerWithCounter, TimelockController } from "contracts/TimelockControllerWithCounter.sol";
import "contracts/utils/Errors.sol" as Errors;
import "../Constants.t.sol";
import "../Utils.t.sol";

//solhint-disable-next-line
// Mostly forked from: https://github.dev/FraxFinance/frax-governance/blob/master/src/TestVeANGLEVotingDelegation.t.sol
contract VeANGLEVotingDelegationTest is Test, Utils {
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes);

    uint256 constant FORK_BLOCK = 17_820_607;

    address public alice;
    address public bob;
    address public charlie;
    address public diane;

    uint256 constant numAccounts = 15;
    address[] public accounts;
    address[] public eoaOwners;
    mapping(address => uint256) addressToPk;

    VyperDeployer public vyperDeployer;

    ERC20 public ANGLE;
    IveANGLE public veANGLE;
    ProposalSender public proposalSender;
    AngleGovernor public angleGovernor;
    AngleGovernor public receiver;
    VeANGLEVotingDelegation public token;
    TimelockControllerWithCounter public mainnetTimelock;

    function setUp() public virtual {
        // Set more realistic timestamps and block numbers
        vm.warp(1_680_000_000);
        vm.roll(17_100_000);

        alice = vm.addr(uint256(keccak256("alice")));
        bob = vm.addr(uint256(keccak256("bob")));
        charlie = vm.addr(uint256(keccak256("charlie")));
        diane = vm.addr(uint256(keccak256("diane")));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(charlie, "Diane");

        address[] memory _accounts = _generateAddresses(numAccounts);
        for (uint256 i = 0; i < numAccounts; ++i) {
            if (i <= 9) {
                accounts.push(_accounts[i]);
            } else if (i > 9) {
                eoaOwners.push(_accounts[i]);
            }
        }

        vyperDeployer = new VyperDeployer();

        (address _mockANGLE, , ) = deployMockANGLE();
        ANGLE = ERC20(_mockANGLE);
        deal(address(ANGLE), mainnetMultisig, 300_000_000e18);

        (address _mockVeANGLE, , ) = deployVeANGLE(vyperDeployer, _mockANGLE, mainnetMultisig);
        veANGLE = IveANGLE(_mockVeANGLE);

        _setupDealAndLockANGLE();

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.roll(block.number + 1152);
        vm.warp(block.timestamp + 10 days);
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
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _generateAddresses(uint256 num) internal returns (address[] memory _accounts) {
        _accounts = new address[](num);
        for (uint256 i = 0; i < num; ++i) {
            (address account, uint256 pk) = makeAddrAndKey(string(abi.encodePacked(i)));
            _accounts[i] = account;
            addressToPk[account] = pk;
        }
    }

    function _setupDealAndLockANGLE() internal {
        uint256 amount = 100_000e18;

        // Give ANGLE balances to every account
        for (uint256 i = 0; i < accounts.length; ++i) {
            deal(address(ANGLE), accounts[i], amount);
            assertEq(ANGLE.balanceOf(accounts[i]), amount, "account gets ANGLE");
        }

        // even distribution of lock time / veANGLE balance
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            vm.startPrank(account, account);
            ANGLE.approve(address(veANGLE), amount);
            veANGLE.create_lock(amount, block.timestamp + (365 days * 4) / (i + 1));
            vm.stopPrank();
            assertGt(veANGLE.balanceOf(account), 0, "veANGLE for an account is always greater than 0");
        }

        assertGt(
            veANGLE.balanceOf(accounts[0]),
            veANGLE.balanceOf(accounts[accounts.length - 1]),
            "Descending veANGLE balances"
        );
    }

    function dealCreateLockANGLE(address account, uint256 amount) public {
        hoax(mainnetMultisig);
        ANGLE.transfer(account, amount);

        vm.startPrank(account, account);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         TESTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Revert if user tries to delegate to themselves with their own address instead of with address(0)
    function test_RevertWhen_IncorrectSelfDelegation() public {
        hoax(accounts[0]);
        vm.expectRevert(IveANGLEVotingDelegation.IncorrectSelfDelegation.selector);
        token.delegate(address(0));
    }

    // Assert that this account has weight themselves when they haven't delegated
    function test_RevertWhen_NoDelegationHasWeight() public {
        assertEq(
            token.getVotes(accounts[0]),
            veANGLE.balanceOf(accounts[0]),
            "getVotes and veANGLE balance are identical"
        );
    }

    // delegate() reverts when the lock is expired
    function test_RevertWhen_CantDelegateLockExpired() public {
        // - 1 days because DelegateCheckpoints are written 1 day in the future
        vm.warp(veANGLE.locked(accounts[1]).end - 1 days);

        hoax(accounts[1]);
        vm.expectRevert(IveANGLEVotingDelegation.CantDelegateLockExpired.selector);
        token.delegate(bob);
    }

    // Account should have no weight at the end of their veANGLE lock
    function test_RevertWhen_NoWeightAfterLockExpires() public {
        vm.warp(veANGLE.locked(accounts[0]).end);
        assertEq(token.getVotes(accounts[0], block.timestamp), 0, "0 weight once lock expires");
    }

    // Test all cases for token.calculateExpiredDelegations();
    function test_WriteNewCheckpointForExpirations() public {
        vm.startPrank(accounts[0]);
        token.calculateExpiredDelegations(accounts[0]);

        // hasnt delegated no checkpoints
        vm.expectRevert(IveANGLEVotingDelegation.NoExpirations.selector);
        token.writeNewCheckpointForExpiredDelegations(accounts[0]);

        token.delegate(bob);

        //checkpoint timestamps are identical
        vm.expectRevert(IveANGLEVotingDelegation.NoExpirations.selector);
        token.writeNewCheckpointForExpiredDelegations(bob);

        // last instant before function will work
        vm.warp(veANGLE.locked(accounts[0]).end - 1 days - 1);

        //total expired ANGLE == 0
        vm.expectRevert(IveANGLEVotingDelegation.NoExpirations.selector);
        token.writeNewCheckpointForExpiredDelegations(bob);

        vm.warp(veANGLE.locked(accounts[0]).end - 1 days);

        uint256 weight = token.getVotes(bob);

        // total expired ANGLE != 0
        token.writeNewCheckpointForExpiredDelegations(bob);
        assertEq(weight, token.getVotes(bob), "same before and after writing this checkpoint");

        vm.warp(veANGLE.locked(accounts[0]).end - 1);

        assertGt(token.getVotes(bob), 0, "bob has voting weight");

        vm.warp(veANGLE.locked(accounts[0]).end);

        assertEq(0, token.getVotes(bob), "0 weight now that lock expired");

        vm.stopPrank();
    }

    function test_Checkpoints() public virtual {
        hoax(accounts[0]);
        token.delegate(bob);

        assertEq(bob, token.delegates(accounts[0]), "account delegated to bob");

        IveANGLEVotingDelegation.DelegateCheckpoint memory dc = token.getCheckpoint(bob, 0);
        assertEq(dc.timestamp, ((block.timestamp / 1 days) * 1 days) + 1 days, "timestamp is next epoch");
        assertEq(dc.normalizedBias, 1_431_643_835_616_437_159_539_200, "Account's bias");
        assertEq(dc.normalizedSlope, 792_744_799_594_114, "Account's normalized slope");
    }

    function test_Delegates() public {
        hoax(accounts[0]);
        token.delegate(bob);

        assertEq(bob, token.delegates(accounts[0]), "Bob is the delegate");
    }

    // Revert delegateBySig when expiry is in the past
    function test_RevertWhen_DelegateBySigBadExpiry() public {
        hoax(accounts[0]);
        vm.expectRevert(IveANGLEVotingDelegation.SignatureExpired.selector);
        token.delegateBySig(address(0), 0, block.timestamp - 1, 0, "", "");
    }

    function test_DelegateBySig() public {
        dealCreateLockANGLE(eoaOwners[0], 100e18);
        (, string memory name, string memory version, uint256 chainId, address verifyingContract, , ) = token
            .eip712Domain();
        bytes32 TYPE_HASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
        );
        bytes32 structHash = keccak256(abi.encode(token.DELEGATION_TYPEHASH(), charlie, 0, block.timestamp));
        bytes32 digest = toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(addressToPk[eoaOwners[0]], digest);

        // call it works
        token.delegateBySig(charlie, 0, block.timestamp, v, r, s);

        // call it again same args nonce throws
        vm.expectRevert(IveANGLEVotingDelegation.InvalidSignatureNonce.selector);
        token.delegateBySig(charlie, 0, block.timestamp, v, r, s);

        assertEq(1, token.$nonces(eoaOwners[0]), "signature nonce incremented");
        assertEq(charlie, token.delegates(eoaOwners[0]), "charlie is now the delegate");
    }

    // Make sure only the final delegate gets weight when delegator delegates twice during the same epoch
    function test_DelegateTwiceSameEpoch() public {
        uint256 weight = token.getVotes(accounts[0]);

        vm.startPrank(accounts[0]);
        token.delegate(charlie);
        token.delegate(alice);
        vm.stopPrank();

        assertEq(weight, token.getVotes(accounts[0]), "Account still has weight before delegation epoch");
        assertEq(0, token.getVotes(charlie), "No weight ever, account immediately redelegated to alice");
        assertEq(0, token.getVotes(alice), "No weight until epoch");

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days - 1);

        assertGt(weight, token.getVotes(accounts[0]), "Voting power decayed slightly");
        assertGt(token.getVotes(accounts[0]), 0, "Account still has voting power");
        assertEq(0, token.getVotes(charlie), "No weight ever, account immediately redelegated to alice");
        assertEq(0, token.getVotes(alice), "No weight until epoch");

        vm.warp(block.timestamp + 1);

        assertEq(0, token.getVotes(accounts[0]), "Account no longer has voting weight");
        assertEq(0, token.getVotes(charlie), "No weight ever, account immediately redelegated to alice");
        assertGt(weight, token.getVotes(alice), "Alice has less weight than original because of decay");
        assertGt(token.getVotes(alice), 0, "Alice has weight");
    }

    // Test transition phase between calling delegate() and delegation going into effect at the next epoch.
    function test_UndelegateReturnsWeight() public {
        vm.startPrank(accounts[0]);

        vm.expectEmit(true, true, true, true);
        emit DelegateVotesChanged(bob, 0, token.getVotes(accounts[0], ((block.timestamp / 1 days) * 1 days) + 1 days));
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(accounts[0], address(0), bob);
        token.delegate(bob);

        assertGt(token.getVotes(accounts[0], block.timestamp), 0, "Account still has weight until epoch");
        assertEq(token.getVotes(bob, block.timestamp), 0, "Delegation not in effect yet");

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts);

        // first delegation in effect
        assertEq(token.getVotes(accounts[0], block.timestamp), 0, "Account delegated all weight");
        assertGt(token.getVotes(bob, block.timestamp), 0, "Bob has delegated weight");

        vm.expectEmit(true, true, true, true);
        emit DelegateVotesChanged(bob, token.getVotes(bob, delegationStarts + 1 days), 0);
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(accounts[0], bob, accounts[0]);
        token.delegate(accounts[0]);

        // first delegation still in effect until next epoch
        assertEq(token.getVotes(accounts[0], block.timestamp), 0, "Account still delegate until next epoch");
        assertGt(token.getVotes(bob, block.timestamp), 0, "Bob still has weight until next epoch");

        vm.warp(delegationStarts + 1 days);

        // undelegate in effect
        assertGt(token.getVotes(accounts[0], block.timestamp), 0, "Account has weight back");
        assertEq(token.getVotes(bob, block.timestamp), 0, "Bob no longer has weight, no longer delegated to");
        vm.stopPrank();
    }

    // Delegating to the same user again without modifying the veANGLE contract will not change their weight
    function test_DoubleDelegate() public {
        hoax(accounts[0]);
        token.delegate(bob);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;
        vm.warp(delegationStarts);

        uint256 weight = token.getVotes(bob, block.timestamp);
        assertGt(weight, 0, "Bob has delegated weight");

        hoax(accounts[0]);
        token.delegate(bob);

        uint256 delegationStarts2 = delegationStarts + 1 days;
        vm.warp(delegationStarts2);
        // delegating again does not add extra weight
        assertGt(weight, token.getVotes(bob, block.timestamp), "Bob's weight didnt change when delegated to again");
    }

    // Ensure delegator doesn't get voting power when switching delegation from account A to account B
    function test_NoDoubleVotingWeight() public {
        // delegate to Bob
        hoax(accounts[0]);
        token.delegate(bob);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts + 1);

        // move delegation to Charlie
        hoax(accounts[0]);
        token.delegate(charlie);

        vm.warp(delegationStarts + 1 days - 1);

        assertGt(token.getVotes(bob, block.timestamp), 0, "Bob still has voting power until next epoch");
        assertEq(
            0,
            token.getVotes(charlie, block.timestamp),
            "Bill should still have no voting power until next epoch"
        );
        assertEq(
            0,
            token.getVotes(accounts[0], block.timestamp),
            "Delegator should still have no voting power until next epoch"
        );

        vm.warp(delegationStarts + 1 days);

        assertEq(0, token.getVotes(bob, block.timestamp), "Bob has no voting power");
        assertGt(token.getVotes(charlie, block.timestamp), 0, "Bill has delegator's weight now");
        assertEq(0, token.getVotes(accounts[0], block.timestamp), "Delegator still has no voting power");
    }

    // Voting weight works as expected including self delegations
    function test_NoDoubleVotingWeightSelfDelegate() public {
        // delegate to A
        hoax(accounts[0]);
        token.delegate(bob);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts);

        // delegate to self
        hoax(accounts[0]);
        token.delegate(accounts[0]);

        assertGt(token.getVotes(bob, block.timestamp), 0, "Bob has voting power until next epoch");
        assertEq(0, token.getVotes(accounts[0], block.timestamp), "Delegator has no voting power until next epoch");

        vm.warp(delegationStarts + 1 days);

        assertGt(token.getVotes(accounts[0], block.timestamp), 0, "Delegator has voting power back");
        assertEq(0, token.getVotes(bob, block.timestamp), "Bob no voting power");

        // delegate to A
        hoax(accounts[0]);
        token.delegate(bob);

        assertGt(token.getVotes(accounts[0], block.timestamp), 0, "Delegator has voting power until next epoch");
        assertEq(0, token.getVotes(bob, block.timestamp), "Bob no voting power until next epoch");

        vm.warp(delegationStarts + 2 days);

        assertGt(token.getVotes(bob, block.timestamp), 0, "Bob should have voting power");
        assertEq(0, token.getVotes(accounts[0], block.timestamp), "Delegator should have no voting power");
    }

    // User can increase their veANGLE lock time and the math is the same as a new lock with same duration and amount
    function test_RelockRedelegate() public {
        uint256 amount = 100_000e18;

        dealCreateLockANGLE(diane, amount);

        hoax(diane);
        token.delegate(bob);

        hoax(mainnetMultisig);
        ANGLE.transfer(charlie, amount);

        vm.startPrank(charlie, charlie);
        ANGLE.approve(address(veANGLE), amount);
        vm.stopPrank();

        uint256 lockEnds = veANGLE.locked(diane).end;

        // the calls to create_lock round differently. Take the weight at + 4 days instead of + 1 days so they're equal
        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 4 days;
        vm.warp(delegationStarts);

        uint256 weight = token.getVotes(bob, block.timestamp);

        mineBlocksBySecond(365 days);

        uint256 weight2 = token.getVotes(bob, block.timestamp);

        assertGt(weight, weight2);

        // original increases their lock time
        hoax(diane, diane);
        veANGLE.increase_unlock_time(block.timestamp + (365 days * 4));

        // new delegator creates a lock with same end
        vm.startPrank(charlie, charlie);
        veANGLE.create_lock(amount, block.timestamp + 365 days * 4);
        token.delegate(alice);
        vm.stopPrank();

        uint256 lockEnds2 = veANGLE.locked(diane).end;

        assertEq(weight2, token.getVotes(bob, block.timestamp), "Bob's weight hasn't changed yet");

        hoax(diane);
        token.delegate(bob);

        assertEq(
            weight2,
            token.getVotes(bob, block.timestamp),
            "Bob's weight still hasn't changed yet, won't change until next epoch"
        );

        uint256 delegationStarts2 = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts2);

        assertGt(token.getVotes(bob, block.timestamp), weight2, "2 delegates weight is larger than 1");
        assertGt(token.getVotes(bob, block.timestamp), weight, "2 delegates weight is larger than 1");

        vm.warp(lockEnds);
        assertGt(token.getVotes(bob, block.timestamp), 0, "Still has voting weight when first delegate's lock expires");
        vm.warp(lockEnds2 - 1);
        assertGt(
            token.getVotes(bob, block.timestamp),
            0,
            "Still has voting weight right before second delegate's lock expires"
        );
        assertEq(
            token.getVotes(bob, block.timestamp),
            token.getVotes(alice, block.timestamp),
            "equivalent to someone else locking same amount, same duration, at same instant"
        );
        vm.warp(lockEnds2);
        assertEq(token.getVotes(bob, block.timestamp), 0, "No weight when all locks expired");
    }

    // Delegating back to yourself works as expected factoring in expirations
    function test_ExpirationDelegationDoesntDoubleSubtract() public {
        hoax(accounts[1]);
        token.delegate(bob);

        uint256 expiration = veANGLE.locked(accounts[1]).end;

        vm.warp(expiration - 1 days);

        // account 1 write the expiration checkpoint
        hoax(accounts[0]);
        token.delegate(bob);

        hoax(accounts[1], accounts[1]);
        veANGLE.increase_unlock_time(block.timestamp + 365 days);

        // expiration and checkpoint in effect
        vm.warp(expiration);

        hoax(accounts[1]);
        token.delegate(accounts[1]);

        // self delegation now in effect
        vm.warp(expiration + 1 days);

        assertEq(
            token.getVotes(bob),
            veANGLE.balanceOf(accounts[0]),
            "Self delegation is equivalent to veANGLE balance"
        );
    }

    // Testing for a bug that was fixed. Essentially when delegator A moves their delegation from B -> C after their
    // original lock expires, B still had some voting power in a specific window that they shouldn't.
    function test_ExpiredLockRedelegateNoVotingWeight() public {
        // A->B at time t
        hoax(accounts[1]);
        token.delegate(bob);

        uint256 expiration = veANGLE.locked(accounts[1]).end;

        // A's lock expires at time t + 1
        // assume proposal with voting snapshot at time t + 2
        vm.warp(expiration + 3);

        // A relocks at time t+3 and delegates to C
        vm.startPrank(accounts[1], accounts[1]);
        veANGLE.withdraw();
        ANGLE.approve(address(veANGLE), ANGLE.balanceOf(accounts[1]));
        veANGLE.create_lock(ANGLE.balanceOf(accounts[1]), block.timestamp + (365 days * 4));
        vm.stopPrank();

        vm.warp(expiration + 4);

        hoax(accounts[1]);
        token.delegate(charlie);

        assertEq(0, token.getVotes(bob, expiration + 2), "Bob has no weight");
    }

    // Fuzz test for proper voting weights with delegations
    function testFuzz_VotingPowerMultiDelegation(uint256 ts) public {
        ts = bound(ts, block.timestamp + 1, veANGLE.locked(accounts[1]).end - 1 days - 1);
        // mirrored from FraxGovernorOmega::_writeCheckpoint
        uint256 tsRoundedToCheckpoint = ((ts / 1 days) * 1 days) + 1 days;

        vm.warp(ts);

        uint256 weight = token.getVotes(accounts[0], block.timestamp);
        uint256 weightA = token.getVotes(accounts[1], block.timestamp);

        assertGt(weight, 0, "Has voting weight");
        assertGt(weightA, 0, "Has voting weight");

        hoax(accounts[0]);
        token.delegate(bob);
        hoax(accounts[1]);
        token.delegate(bob);

        assertLe(
            weight,
            token.getVotes(accounts[0], block.timestamp - 1),
            "accounts[0] still has weight before delegation"
        );
        assertEq(
            weight,
            token.getVotes(accounts[0], block.timestamp),
            "accounts[0] still has weight until next checkpoint time"
        );

        assertLe(
            weightA,
            token.getVotes(accounts[1], block.timestamp - 1),
            "accounts[1] still has weight before delegation"
        );
        assertEq(
            weightA,
            token.getVotes(accounts[1], block.timestamp),
            "accounts[1] still has weight until next checkpoint time"
        );

        assertEq(0, token.getVotes(bob, block.timestamp - 1), "delegate has no weight before delegation");
        assertEq(0, token.getVotes(bob, block.timestamp), "delegate has no weight until the next checkpoint time");

        vm.warp(tsRoundedToCheckpoint - 1);

        // original still has weight until the next checkpoint Time
        uint256 weight2 = token.getVotes(accounts[0], block.timestamp);
        assertGt(weight2, 0, "accounts[0] has weight until delegation takes effect");
        assertGe(weight, weight2, "weight has slightly decayed");

        uint256 weightA2 = token.getVotes(accounts[1], block.timestamp);
        assertGt(weightA2, 0, "accounts[1] has weight until delegation takes effect");
        assertGe(weightA, weightA2, "weight has slightly decayed");

        assertEq(0, token.getVotes(bob, block.timestamp), "delegate has no weight until the next checkpoint time");

        vm.warp(tsRoundedToCheckpoint);

        assertEq(
            0,
            token.getVotes(accounts[0], block.timestamp),
            "accounts[0]'s delegation kicks in so they have no weight"
        );
        assertEq(
            0,
            token.getVotes(accounts[1], block.timestamp),
            "accounts[1]'s delegation kicks in so they have no weight"
        );

        uint256 bobWeight = token.getVotes(bob, block.timestamp);
        // original's delegation hits in so delegatee has their weight
        assertGt(bobWeight, weight2, "Bob has both delegator's weight");
        assertGe(weight2 + weightA2, bobWeight, "Weight has decayed slightly");
    }

    // Fuzz asserts that our delegated weight calculations == veANGLE.balanceOf() at all time points before lock expiry.
    function testFuzz_FirstVotingPowerExpiration(uint256 ts) public {
        hoax(accounts[0]);
        token.delegate(bob);
        hoax(accounts[1]);
        token.delegate(bob);

        ts = bound(ts, veANGLE.locked(accounts[1]).end, veANGLE.locked(accounts[0]).end - 1); // lock expiry

        vm.warp(ts);

        uint256 weight = token.getVotes(accounts[0], block.timestamp);
        uint256 veANGLEBalance = veANGLE.balanceOf(accounts[0], block.timestamp);
        uint256 weightA = token.getVotes(accounts[1], block.timestamp);
        uint256 delegateWeight = token.getVotes(bob, block.timestamp);
        assertEq(weight, 0, "Delegator has no weight");
        assertEq(weightA, 0, "Delegator has no weight");
        // veANGLE.balanceOf() will return the amount of ANGLE you have when your lock expires. We want it to go to zero,
        // because a user could lock ANGLE, delegate, time passes, lock expires, withdraw ANGLE but the delegate would
        // still have voting power to mitigate this, delegated voting power goes to 0 when the lock expires.
        assertEq(delegateWeight, veANGLEBalance, "delegate's weight == veANGLE balance");
    }

    // Fuzz asserts that our delegated weight calculations == veANGLE.balanceOf() at all time points before lock expiry.
    // with various amounts
    function testFuzz_DelegationVeANGLEEquivalenceBeforeExpiration(uint256 amount, uint256 ts) public {
        amount = bound(amount, 100e18, 1_500_000e18);

        vm.startPrank(mainnetMultisig);
        ANGLE.transfer(charlie, amount);
        ANGLE.transfer(alice, amount);
        vm.stopPrank();

        assertEq(ANGLE.balanceOf(charlie), amount, "Has ANGLE");
        assertEq(ANGLE.balanceOf(alice), amount, "Has ANGLE");

        vm.startPrank(charlie, charlie);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        vm.startPrank(alice, alice);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        hoax(charlie);
        token.delegate(bob);
        hoax(alice);
        token.delegate(bob);

        uint256 nowRoundedToCheckpoint = ((block.timestamp / 1 days) * 1 days) + 1 days;

        ts = bound(ts, nowRoundedToCheckpoint, veANGLE.locked(charlie).end - 1); //lock expiry

        vm.warp(ts);

        uint256 weight = token.getVotes(charlie, block.timestamp);
        uint256 veANGLEBalance = veANGLE.balanceOf(charlie, block.timestamp);
        uint256 weightA = token.getVotes(alice, block.timestamp);
        uint256 veANGLEBalanceA = veANGLE.balanceOf(alice, block.timestamp);
        uint256 delegateWeight = token.getVotes(bob, block.timestamp);
        assertEq(weight, 0, "Delegator has no weight");
        assertEq(weightA, 0, "Delegator has no weight");
        assertEq(
            veANGLEBalance + veANGLEBalanceA,
            delegateWeight,
            "delegate's weight == veANGLE balance of both delegators"
        );
    }

    // Fuzz asserts all weight expired at various time points following veANGLE lock expiry
    function testFuzz_DelegationVeANGLEAfterExpiry(uint256 amount, uint256 ts) public {
        amount = bound(amount, 100e18, 1_500_000e18);

        vm.startPrank(mainnetMultisig);
        ANGLE.transfer(charlie, amount);
        ANGLE.transfer(alice, amount);
        vm.stopPrank();

        assertEq(ANGLE.balanceOf(charlie), amount, "Has ANGLE");
        assertEq(ANGLE.balanceOf(alice), amount, "Has ANGLE");

        vm.startPrank(charlie, charlie);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        vm.startPrank(alice, alice);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        hoax(charlie);
        token.delegate(bob);
        hoax(alice);
        token.delegate(bob);

        ts = bound(ts, veANGLE.locked(charlie).end, veANGLE.locked(charlie).end + (365 days * 10));

        vm.warp(ts);

        uint256 weight = token.getVotes(charlie, block.timestamp);
        uint256 weightA = token.getVotes(alice, block.timestamp);
        uint256 delegateWeight = token.getVotes(bob, block.timestamp);
        assertEq(weight, 0, "Delegator has no weight after lock expires");
        assertEq(weightA, 0, "Delegator has no weight after lock expires");
        assertEq(delegateWeight, 0, "Delegate has no weight after lock expires");
    }

    // Fuzz expirations with various amounts
    function testFuzz_CheckpointExpiration(uint256 amount) public {
        // start local and fork test at same point in time
        vm.warp(1_701_328_824);
        vm.roll(FORK_BLOCK + 10_000);

        amount = bound(amount, 100e18, 1_500_000e18);
        uint256 start = ((block.timestamp / 1 days) * 1 days) + 1 days;
        vm.warp(start);

        vm.startPrank(mainnetMultisig);
        ANGLE.transfer(charlie, amount);
        ANGLE.transfer(alice, amount);
        vm.stopPrank();

        vm.startPrank(charlie, charlie);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        token.delegate(bob);
        vm.stopPrank();

        vm.startPrank(alice, alice);
        ANGLE.approve(address(veANGLE), amount);
        vm.stopPrank();

        vm.warp(start + 1 days);
        uint256 weight = token.getVotes(bob, block.timestamp);
        uint256 end = veANGLE.locked(charlie).end;

        vm.warp(end);

        vm.startPrank(alice, alice);
        veANGLE.create_lock(amount, block.timestamp + (365 days * 4));
        token.delegate(bob);
        vm.stopPrank();

        assertEq(0, token.getVotes(bob, block.timestamp), "Delegate has no weight until checkpoint epoch");

        vm.warp(((end / 1 days) * 1 days) + 1 days);
        assertGt(token.getVotes(bob, block.timestamp), 0, "Delegate has weight now");
        assertLt(weight, token.getVotes(bob, block.timestamp), "First delegation expires as expected");

        // the calls to create_lock round differently. Take the weight at + 2 days instead of + 1 days so they're equal
        vm.warp(((end / 1 days) * 1 days) + 2 days);
        // test expiration worked correctly
        assertEq(weight, token.getVotes(bob, block.timestamp), "First delegation expires as expected");
    }

    // Fuzz tests expirations with different amounts and different lock expiry
    function testFuzz_MultiDurationMultiAmount(uint256 amount, uint256 amount2, uint256 ts, uint256 ts2) public {
        amount = bound(amount, 100e18, 1_500_000e18);
        amount2 = bound(amount2, 100e18, 1_500_000e18);
        ts = bound(ts, block.timestamp + 30 days, block.timestamp + (365 days * 4));
        ts2 = bound(ts2, block.timestamp + 30 days, block.timestamp + (365 days * 4));

        vm.startPrank(mainnetMultisig);
        ANGLE.transfer(charlie, amount);
        ANGLE.transfer(alice, amount2);
        vm.stopPrank();

        assertEq(ANGLE.balanceOf(charlie), amount, "Has ANGLE");
        assertEq(ANGLE.balanceOf(alice), amount2, "Has ANGLE");

        vm.startPrank(charlie, charlie);
        ANGLE.approve(address(veANGLE), amount);
        veANGLE.create_lock(amount, ts);
        vm.stopPrank();

        vm.startPrank(alice, alice);
        ANGLE.approve(address(veANGLE), amount2);
        veANGLE.create_lock(amount2, ts2);
        vm.stopPrank();

        hoax(charlie);
        token.delegate(bob);
        hoax(alice);
        token.delegate(bob);

        uint256 billEnd = veANGLE.locked(charlie).end;
        uint256 aliceEnd = veANGLE.locked(alice).end;

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days);
        uint256 weight = token.getVotes(bob, block.timestamp);

        vm.warp(billEnd < aliceEnd ? billEnd : aliceEnd);
        uint256 weight2 = token.getVotes(bob, block.timestamp);
        assertGt(weight, weight2, "Some weight expired");

        vm.warp(billEnd > aliceEnd ? billEnd : aliceEnd);
        assertEq(0, token.getVotes(bob, block.timestamp), "No longer has voting weight");
        // equal in case they expire at the same time
        assertGe(weight2, token.getVotes(bob, block.timestamp), "More weight has expired");
    }

    // Testing for overflow of packed structs
    function test_BoundsOfDelegationStructs() public virtual {
        vm.warp(1_680_274_875 + (365 days * 100)); // move time forward so bias is larger
        uint256 amount = 10_000e18;
        uint256 totalVeANGLE;
        address delegate = address(uint160(1_000_000));

        for (uint256 i = 100; i < 1000; ++i) {
            address account = address(uint160(i));
            deal(address(ANGLE), account, amount);

            vm.startPrank(account, account);
            ANGLE.approve(address(veANGLE), amount);
            veANGLE.create_lock(amount, block.timestamp + (365 days * 4));

            token.delegate(delegate);
            vm.stopPrank();
        }

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days);

        for (uint256 i = 100; i < 1000; ++i) {
            address account = address(uint160(i));
            totalVeANGLE += veANGLE.balanceOf(account, block.timestamp);
        }
        assertEq(
            totalVeANGLE,
            token.getVotes(delegate, block.timestamp),
            "total delegated voting weight is equal to total veANGLE balances"
        );

        uint256 lockEnd = veANGLE.locked(address(uint160(100))).end;
        (uint256 bias, uint128 slope) = token.$expiredDelegations(delegate, lockEnd);
        assertLt(bias, type(uint96).max, "For communicating intent of test");
        assertLt(slope, type(uint64).max, "For communicating intent of test");

        vm.warp(lockEnd);

        // expirations are properly accounted for
        assertEq(0, token.getVotes(delegate, block.timestamp), "Everything expired properly");
    }

    // Create a ton of random checkpoints
    function test_FuzzManyCheckpoints(uint256 daysDelta, uint256 timestamp) public virtual {
        daysDelta = bound(daysDelta, 3 days, 60 days);
        timestamp = bound(timestamp, 604_800, 126_748_800); // startTs, endTs

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days); // 604800

        uint256 amount = 10_000e18;
        address delegate = address(uint160(1_000_000));

        for (uint256 i = 100; i < (365 * 4) + 100; i += daysDelta / 1 days) {
            address account = address(uint160(i));
            deal(address(ANGLE), account, amount);

            vm.startPrank(account, account);
            ANGLE.approve(address(veANGLE), amount);
            veANGLE.create_lock(amount, block.timestamp + (365 days * 4));

            token.delegate(delegate);
            vm.stopPrank();
            // Go forward daysDelta days
            vm.warp(block.timestamp + daysDelta);

            assertTrue(token.getVotes(delegate, timestamp + daysDelta) >= 0);
        }
    }
}
