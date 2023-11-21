// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { Strings } from "oz/utils/Strings.sol";
import { MessageHashUtils } from "oz/utils/cryptography/MessageHashUtils.sol";
import { GovernorCountingSimple } from "oz/governance/extensions/GovernorCountingSimple.sol";
import { GovernorVotesQuorumFraction } from "oz/governance/extensions/GovernorVotesQuorumFraction.sol";

import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import "forge-std/console.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { VeANGLEVotingDelegation } from "contracts/VeANGLEVotingDelegation.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../external/FixedPointMathLib.t.sol";
import "../Utils.t.sol";

//solhint-disable-next-line
// Mostly forked from: https://github.com/ScopeLift/flexible-voting/blob/4399694c1a70d9e236c4c072802bfbe8e4951bf0/test/GovernorCountingFractional.t.sol
contract GovernorCountingFractionalTest is Test {
    using FixedPointMathLib for uint256;

    event MockFunctionCalled();
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
    event VoteCastWithParams(
        address indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 weight,
        string reason,
        bytes params
    );
    event ProposalExecuted(uint256 proposalId);
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 voteStart,
        uint256 voteEnd,
        string description
    );
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);

    // We use a min of 1e4 to avoid flooring votes to 0.
    uint256 constant MIN_VOTE_WEIGHT = 1e4;
    // This is the vote storage slot size on the Fractional Governor contract.
    uint256 constant MAX_VOTE_WEIGHT = type(uint128).max;
    uint256 constant TOTAL_SUPPLY = type(uint184).max;

    // See OZ's EIP712._domainSeparatorV4() function for how this was computed.
    // This can also be obtained from GovernorCountingFractional with:
    //   console2.log(uint(_domainSeparatorV4()))
    bytes32 EIP712_DOMAIN_SEPARATOR = bytes32(0x7acea78d43ca3863e8417dada982c13eebe6b1271377203539b40d80c0581f2e);

    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    struct FractionalVoteSplit {
        uint256 percentFor; // wad
        uint256 percentAgainst; // wad
        uint256 percentAbstain; // wad
    }

    struct Voter {
        address addr;
        uint256 weight;
        uint8 support;
        FractionalVoteSplit voteSplit;
    }

    struct VoteData {
        uint128 forVotes;
        uint128 againstVotes;
        uint128 abstainVotes;
    }

    struct Proposal {
        uint256 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    ProposalSender public proposalSender;
    AngleGovernor public governor;
    AngleGovernor public receiver;
    IVotes public token;
    TimelockController public mainnetTimelock;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        vm.roll(block.number + 1152);
        vm.warp(block.timestamp + 10 days);
        token = new VeANGLEVotingDelegation(address(veANGLE), "veANGLE Delegation", "1");

        mainnetTimelock = new TimelockController(1 days, proposers, executors, address(this));
        governor = new AngleGovernor(
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
        receiver = governor;
        mainnetTimelock.grantRole(mainnetTimelock.PROPOSER_ROLE(), address(governor));
        mainnetTimelock.grantRole(mainnetTimelock.CANCELLER_ROLE(), mainnetMultisig);
        // mainnetTimelock.renounceRole(mainnetTimelock.TIMELOCK_ADMIN_ROLE(), address(this));
        proposalSender = new ProposalSender(mainnetLzEndpoint);
        proposalSender.transferOwnership(address(governor));

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.getPastTotalSupply.selector),
            abi.encode(TOTAL_SUPPLY)
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                BEGIN HELPER FUNCTIONS                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _encodeStateBitmap(IGovernor.ProposalState proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    function _getQuorum() internal returns (uint256 _weight) {
        _weight =
            (token.getPastTotalSupply(block.number) * governor.quorumNumerator(block.timestamp)) /
            governor.quorumDenominator();

        // if the weight is too large (> type(uint128).max) decrease the totalSupply
        // for it to be enough to be above quorum
        if (_weight > MAX_VOTE_WEIGHT) {
            _weight = MAX_VOTE_WEIGHT;
            uint256 _tmpTotalSupply = _supplyInverseQuorum(_weight);
            vm.mockCall(
                address(token),
                abi.encodeWithSelector(token.getPastTotalSupply.selector),
                abi.encode(_tmpTotalSupply)
            );
        }
    }

    function _supplyInverseQuorum(uint256 quorum) internal view returns (uint256) {
        return (governor.quorumDenominator() * quorum) / governor.quorumNumerator(block.timestamp);
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        bytes32 TYPE_HASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 _hashedName = keccak256(bytes("AngleGovernor"));
        bytes32 _hashedVersion = keccak256(bytes("1"));
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(governor)));
    }

    function _getSimpleProposal() internal view returns (Proposal memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0; // no ETH will be sent
        calldatas[0] = abi.encodeWithSelector(GovernorVotesQuorumFraction.updateQuorumNumerator.selector, 11);
        string memory description = "A modest proposal";
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        return Proposal(proposalId, targets, values, calldatas, description);
    }

    function _createAndSubmitProposal() internal returns (uint256 proposalId) {
        // Build a proposal.
        Proposal memory _proposal = _getSimpleProposal();

        vm.expectEmit(true, true, true, true);
        emit ProposalCreated(
            _proposal.id,
            address(this),
            _proposal.targets,
            _proposal.values,
            new string[](_proposal.targets.length), // Signatures
            _proposal.calldatas,
            block.timestamp + governor.votingDelay(),
            block.timestamp + governor.votingDelay() + governor.votingPeriod(),
            _proposal.description
        );

        // Submit the proposal.
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.getPastVotes.selector, address(this)),
            abi.encode(governor.proposalThreshold())
        );
        proposalId = governor.propose(_proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description);
        vm.mockCall(address(token), abi.encodeWithSelector(token.getPastVotes.selector, address(this)), abi.encode(0));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Advance proposal to active state.
        vm.warp(governor.proposalSnapshot(proposalId) + 1);
        vm.roll(block.number + governor.$votingDelayBlocks() + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
    }

    function _executeProposal() internal {
        Proposal memory _rawProposalInfo = _getSimpleProposal();

        vm.expectEmit(true, true, true, true);
        emit ProposalExecuted(_rawProposalInfo.id);

        // Ensure that the other contract is invoked.
        vm.expectEmit(true, true, true, true);
        emit QuorumNumeratorUpdated(initialQuorumNumerator, 11);

        governor.execute(
            _rawProposalInfo.targets,
            _rawProposalInfo.values,
            _rawProposalInfo.calldatas,
            keccak256(bytes(_rawProposalInfo.description))
        );
    }

    function _setupNominalVoters(uint256[4] memory weights) internal returns (Voter[4] memory voters) {
        Voter memory voter;
        for (uint8 _i; _i < voters.length; _i++) {
            voter = voters[_i];
            voter.addr = _randomAddress();
            voter.weight = bound(weights[_i], MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT / 4);
            voter.support = _randomSupportType(weights[_i]);
        }
    }

    function _assumeAndLabelFuzzedVoter(address _addr) internal returns (address) {
        return _assumeAndLabelFuzzedAddress(_addr, "voter");
    }

    function _assumeAndLabelFuzzedAddress(address _addr, string memory _name) internal returns (address) {
        while (_addr == address(this)) _addr = _randomAddress();
        vm.assume(_addr > address(0));
        vm.label(_addr, _name);
        return _addr;
    }

    function _randomAddress() internal returns (address _addr) {
        _addr = address(uint160(uint256(nextUser)));
        nextUser = keccak256(abi.encodePacked(_addr));
    }

    function _randomSupportType(uint256 salt) public returns (uint8) {
        return uint8(bound(salt, 0, uint8(GovernorCountingSimple.VoteType.Abstain)));
    }

    function _randomVoteSplit(FractionalVoteSplit memory _voteSplit) public returns (FractionalVoteSplit memory) {
        _voteSplit.percentFor = bound(_voteSplit.percentFor, 0, 1e18);
        _voteSplit.percentAgainst = bound(_voteSplit.percentAgainst, 0, (1e18 - _voteSplit.percentFor));
        _voteSplit.percentAbstain = 1e18 - (_voteSplit.percentFor + _voteSplit.percentAgainst);
        return _voteSplit;
    }

    // Sets up up a 4-Voter array with specified weights and voteSplits, and random supportTypes.
    function _setupFractionalVoters(
        uint256[4] memory weights,
        FractionalVoteSplit[4] memory voteSplits
    ) internal returns (Voter[4] memory voters) {
        voters = _setupNominalVoters(weights);

        Voter memory voter;
        for (uint8 _i; _i < voters.length; _i++) {
            voter = voters[_i];
            FractionalVoteSplit memory split = voteSplits[_i];
            // If the voteSplit has been initialized, we use it.
            if (_isVotingFractionally(split)) {
                // If the values are valid, _randomVoteSplit won't change them.
                voter.voteSplit = _randomVoteSplit(split);
            }
        }
    }

    function _mintAndDelegateToVoter(Voter memory voter) internal {
        uint256 prevGetPastVotes;
        try token.getPastVotes(voter.addr, block.timestamp - 1) returns (uint256 returnCall) {
            prevGetPastVotes = returnCall;
        } catch {}
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.getPastVotes.selector, address(voter.addr)),
            abi.encode(voter.weight)
        );
    }

    function _mintAndDelegateToVoters(
        Voter[4] memory voters
    ) internal returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) {
        Voter memory voter;

        for (uint8 _i = 0; _i < voters.length; _i++) {
            voter = voters[_i];
            _mintAndDelegateToVoter(voter);

            if (_isVotingFractionally(voter.voteSplit)) {
                forVotes += uint128(voter.weight.mulWadDown(voter.voteSplit.percentFor));
                againstVotes += uint128(voter.weight.mulWadDown(voter.voteSplit.percentAgainst));
                abstainVotes += uint128(voter.weight.mulWadDown(voter.voteSplit.percentAbstain));
            } else {
                if (voter.support == uint8(GovernorCountingSimple.VoteType.For)) {
                    forVotes += voter.weight;
                }
                if (voter.support == uint8(GovernorCountingSimple.VoteType.Against)) {
                    againstVotes += voter.weight;
                }
                if (voter.support == uint8(GovernorCountingSimple.VoteType.Abstain)) {
                    abstainVotes += voter.weight;
                }
            }
        }
    }

    // If we've set up the voteSplit, this voter will vote fractionally
    function _isVotingFractionally(FractionalVoteSplit memory voteSplit) public pure returns (bool) {
        return voteSplit.percentFor > 0 || voteSplit.percentAgainst > 0 || voteSplit.percentAbstain > 0;
    }

    function _castVotes(Voter memory _voter, uint256 _proposalId) internal {
        if (_voter.weight == 0) return;
        assertFalse(governor.hasVoted(_proposalId, _voter.addr));

        bytes memory fractionalizedVotes;
        FractionalVoteSplit memory voteSplit = _voter.voteSplit;

        if (_isVotingFractionally(voteSplit)) {
            fractionalizedVotes = abi.encodePacked(
                uint128(_voter.weight.mulWadDown(voteSplit.percentAgainst)),
                uint128(_voter.weight.mulWadDown(voteSplit.percentFor)),
                uint128(_voter.weight.mulWadDown(voteSplit.percentAbstain))
            );
            vm.expectEmit(true, true, true, true);
            emit VoteCastWithParams(
                _voter.addr,
                _proposalId,
                _voter.support,
                _voter.weight,
                "Yay",
                fractionalizedVotes
            );
        } else {
            vm.expectEmit(true, true, true, true);
            emit VoteCast(_voter.addr, _proposalId, _voter.support, _voter.weight, "Yay");
        }

        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Yay", fractionalizedVotes);

        assertTrue(governor.hasVoted(_proposalId, _voter.addr));
    }

    function _castVotes(Voter[4] memory voters, uint256 _proposalId) internal {
        for (uint8 _i = 0; _i < voters.length; _i++) {
            _castVotes(voters[_i], _proposalId);
        }
    }

    function _fractionalGovernorHappyPathTest(Voter[4] memory voters) public {
        uint256 _initGovBalance = address(governor).balance;
        uint256 _initReceiverBalance = address(receiver).balance;

        (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) = _mintAndDelegateToVoters(voters);
        uint256 _proposalId = _createAndSubmitProposal();
        _castVotes(voters, _proposalId);

        // Jump ahead so that we're outside of the proposal's voting period.
        vm.warp(governor.proposalDeadline(_proposalId) + 1);
        vm.roll(governor.$snapshotTimestampToSnapshotBlockNumber(governor.proposalSnapshot(_proposalId)) + 1);

        (uint256 againstVotesCast, uint256 forVotesCast, uint256 abstainVotesCast) = governor.proposalVotes(
            _proposalId
        );

        assertEq(againstVotes, againstVotesCast);
        assertEq(forVotes, forVotesCast);
        assertEq(abstainVotes, abstainVotesCast);

        IGovernor.ProposalState status = IGovernor.ProposalState(uint32(governor.state(_proposalId)));
        if (
            forVotes > againstVotes &&
            (forVotes + abstainVotes) >= governor.quorum(governor.proposalSnapshot(_proposalId))
        ) {
            assertEq(uint8(status), uint8(IGovernor.ProposalState.Succeeded));
            _executeProposal();
        } else {
            assertEq(uint8(status), uint8(IGovernor.ProposalState.Defeated));

            Proposal memory _rawProposalInfo = _getSimpleProposal();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGovernor.GovernorUnexpectedProposalState.selector,
                    _rawProposalInfo.id,
                    IGovernor.ProposalState.Defeated,
                    _encodeStateBitmap(IGovernor.ProposalState.Succeeded) |
                        _encodeStateBitmap(IGovernor.ProposalState.Queued)
                )
            );
            governor.execute(
                _rawProposalInfo.targets,
                _rawProposalInfo.values,
                _rawProposalInfo.calldatas,
                keccak256(bytes(_rawProposalInfo.description))
            );
        }

        // No ETH should have moved.
        assertEq(address(governor).balance, _initGovBalance);
        assertEq(address(receiver).balance, _initReceiverBalance);
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        (, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        return governor.quorum(governor.proposalSnapshot(proposalId)) <= forVotes + abstainVotes;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 END HELPER FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function test_Deployment() public {
        assertEq(governor.name(), "AngleGovernor");
        assertEq(address(governor.token()), address(token));
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain&params=fractional");
    }

    function testFuzz_NominalBehaviorIsUnaffected(uint256[4] memory weights) public {
        Voter[4] memory voters = _setupNominalVoters(weights);
        _fractionalGovernorHappyPathTest(voters);
    }

    function testFuzz_VotingWithFractionalizedParams(
        uint256[4] memory weights,
        FractionalVoteSplit[4] memory _voteSplits
    ) public {
        Voter[4] memory voters = _setupFractionalVoters(weights, _voteSplits);
        _fractionalGovernorHappyPathTest(voters);
    }

    function testFuzz_NominalVotingWithFractionalizedParamsAndSignature(uint256 _weight) public {
        Voter memory _voter;
        uint256 _privateKey;
        (_voter.addr, _privateKey) = makeAddrAndKey("voter");
        vm.assume(_voter.addr != address(this));

        _voter.weight = bound(_weight, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        _voter.support = _randomSupportType(_weight);

        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();

        bytes32 _voteMessage = keccak256(
            abi.encode(governor.BALLOT_TYPEHASH(), _proposalId, _voter.support, _voter.addr, 0)
        );

        bytes memory signature;
        {
            bytes32 _voteMessageHash = keccak256(abi.encodePacked("\x19\x01", EIP712_DOMAIN_SEPARATOR, _voteMessage));
            vm.prank(_voter.addr);
            (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_privateKey, _voteMessageHash);
            signature = abi.encodePacked(_r, _s, _v);
        }
        governor.castVoteBySig(_proposalId, _voter.support, _voter.addr, signature);

        (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) = governor.proposalVotes(
            _proposalId
        );
        if (_voter.support == uint8(GovernorCountingSimple.VoteType.For)) {
            assertEq(_voter.weight, _actualForVotes);
        }
        if (_voter.support == uint8(GovernorCountingSimple.VoteType.Against)) {
            assertEq(_voter.weight, _actualAgainstVotes);
        }
        if (_voter.support == uint8(GovernorCountingSimple.VoteType.Abstain)) {
            assertEq(_voter.weight, _actualAbstainVotes);
        }
    }

    function testFuzz_VotingWithFractionalizedParamsAndSignature(
        uint256 _weight,
        FractionalVoteSplit memory _voteSplit
    ) public {
        Voter memory _voter;
        uint256 _privateKey;
        (_voter.addr, _privateKey) = makeAddrAndKey("voter");
        vm.assume(_voter.addr != address(this));

        _voter.weight = bound(_weight, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        _voter.support = _randomSupportType(_weight);
        _voter.voteSplit = _randomVoteSplit(_voteSplit);

        uint128 _forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor));
        uint128 _againstVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentAgainst));
        uint128 _abstainVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentAbstain));
        bytes memory _fractionalizedVotes = abi.encodePacked(_againstVotes, _forVotes, _abstainVotes);

        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();

        bytes32 _voteMessage = keccak256(
            abi.encode(
                governor.EXTENDED_BALLOT_TYPEHASH(),
                _proposalId,
                _voter.support,
                _voter.addr,
                0,
                keccak256(bytes("I have my reasons")),
                keccak256(_fractionalizedVotes)
            )
        );

        bytes memory signature;
        {
            bytes32 _voteMessageHash = keccak256(abi.encodePacked("\x19\x01", EIP712_DOMAIN_SEPARATOR, _voteMessage));
            vm.prank(_voter.addr);
            (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_privateKey, _voteMessageHash);
            signature = abi.encodePacked(_r, _s, _v);
        }

        governor.castVoteWithReasonAndParamsBySig(
            _proposalId,
            _voter.support,
            _voter.addr,
            "I have my reasons",
            _fractionalizedVotes,
            signature
        );

        (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) = governor.proposalVotes(
            _proposalId
        );
        assertEq(_forVotes, _actualForVotes);
        assertEq(_againstVotes, _actualAgainstVotes);
        assertEq(_abstainVotes, _actualAbstainVotes);
    }

    function testFuzz_VoteSplitsCanBeMaxedOut(uint256[4] memory _weights, uint8 _maxSplit) public {
        Voter[4] memory _voters = _setupNominalVoters(_weights);

        // Set one of the splits to 100% and all of the others to 0%.
        uint256 _forSplit;
        uint256 _againstSplit;
        uint256 _abstainSplit;
        if (_maxSplit % 3 == 0) _forSplit = 1.0e18;
        if (_maxSplit % 3 == 1) _againstSplit = 1.0e18;
        if (_maxSplit % 3 == 2) _abstainSplit = 1.0e18;
        _voters[0].voteSplit = FractionalVoteSplit(_forSplit, _againstSplit, _abstainSplit);

        // We don't actually want these users to vote.
        _voters[1].weight = 0;
        _voters[2].weight = 0;
        _voters[3].weight = 0;

        _fractionalGovernorHappyPathTest(_voters);
    }

    function testFuzz_UsersCannotVoteWithZeroWeight(address _voterAddr) public {
        _assumeAndLabelFuzzedVoter(_voterAddr);

        // They must have no weight at the time of the proposal snapshot.
        vm.mockCall(address(token), abi.encodeWithSelector(token.getVotes.selector, _voterAddr), abi.encode(0));
        vm.mockCall(address(token), abi.encodeWithSelector(token.getPastVotes.selector, _voterAddr), abi.encode(0));
        vm.assume(token.getVotes(_voterAddr) == 0);

        uint256 _proposalId = _createAndSubmitProposal();

        // Attempt to cast nominal votes.
        vm.prank(_voterAddr);
        vm.expectRevert(Errors.GovernorCountingFractionalNoWeight.selector);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            uint8(GovernorCountingSimple.VoteType.For),
            "I hope no one catches me doing this!",
            new bytes(0) // No data, this is a nominal vote.
        );

        // Attempt to cast fractional votes.
        vm.prank(_voterAddr);
        vm.expectRevert(Errors.GovernorCountingFractionalNoWeight.selector);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            uint8(GovernorCountingSimple.VoteType.For),
            "I'm so bad",
            abi.encodePacked(type(uint128).max, type(uint128).max, type(uint128).max)
        );
    }

    function testFuzz_VotingWithMixedFractionalAndNominalVoters(
        uint256[4] memory weights,
        FractionalVoteSplit[4] memory voteSplits,
        bool[4] memory userIsFractional
    ) public {
        FractionalVoteSplit memory _emptyVoteSplit;
        for (uint256 _i; _i < userIsFractional.length; _i++) {
            if (userIsFractional[_i]) {
                // If the user *is* a fractional user, we randomize the splits and make sure they sum to
                // 1e18.
                voteSplits[_i] = _randomVoteSplit(voteSplits[_i]);
            } else {
                // If the user is *not* a fractional user, we clear the split info from the array. This will
                // cause them to cast their vote nominally.
                voteSplits[_i] = _emptyVoteSplit;
            }
        }
        Voter[4] memory voters = _setupFractionalVoters(weights, voteSplits);
        _fractionalGovernorHappyPathTest(voters);
    }

    function testFuzz_FractionalVotingCannotExceedOverallWeight(
        uint256[4] memory weights,
        FractionalVoteSplit[4] memory voteSplits,
        uint256 exceedPercentage,
        uint256 voteTypeToExceed
    ) public {
        exceedPercentage = bound(exceedPercentage, 0.01e18, 1e18); // Between 1 & 100 percent as a wad
        voteTypeToExceed = _randomSupportType(voteTypeToExceed);

        for (uint256 _i; _i < voteSplits.length; _i++) {
            voteSplits[_i] = _randomVoteSplit(voteSplits[_i]);
        }

        Voter[4] memory voters = _setupFractionalVoters(weights, voteSplits);
        Voter memory voter = voters[0];
        FractionalVoteSplit memory voteSplit = voter.voteSplit;

        if (voteTypeToExceed == 0) voteSplit.percentFor += exceedPercentage;
        if (voteTypeToExceed == 1) voteSplit.percentAgainst += exceedPercentage;
        if (voteTypeToExceed == 2) voteSplit.percentAbstain += exceedPercentage;

        assertGt(voteSplit.percentFor + voteSplit.percentAgainst + voteSplit.percentAbstain, 1e18);

        _mintAndDelegateToVoters(voters);
        uint256 _proposalId = _createAndSubmitProposal();
        bytes memory fractionalizedVotes;

        fractionalizedVotes = abi.encodePacked(
            uint128(voter.weight.mulWadDown(voteSplit.percentAgainst)),
            uint128(voter.weight.mulWadDown(voteSplit.percentFor)),
            uint128(voter.weight.mulWadDown(voteSplit.percentAbstain))
        );

        vm.prank(voter.addr);
        vm.expectRevert(Errors.GovernorCountingFractionalVoteExceedWeight.selector);
        governor.castVoteWithReasonAndParams(_proposalId, voter.support, "Yay", fractionalizedVotes);
    }

    function testFuzz_OverFlowWeightIsHandledForNominalVoters(uint256 _weight, address _voterAddr) public {
        Voter memory voter;
        voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);
        // The weight cannot overflow the max supply for the token, but must overflow the
        // max for the GovernorFractional contract.
        voter.weight = bound(_weight, MAX_VOTE_WEIGHT + 1, token.getPastTotalSupply(block.number));
        voter.support = _randomSupportType(_weight);

        _mintAndDelegateToVoter(voter);
        uint256 _proposalId = _createAndSubmitProposal();

        bytes memory emptyVotingParams;
        vm.prank(voter.addr);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, voter.weight));
        governor.castVoteWithReasonAndParams(_proposalId, voter.support, "Yay", emptyVotingParams);
    }

    function testFuzz_OverFlowWeightIsHandledForFractionalVoters(
        address _voterAddr,
        uint256 _weight,
        bool[3] calldata voteTypeToOverflow
    ) public {
        Voter memory voter;
        voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);
        // The weight cannot overflow the max supply for the token, but must overflow the
        // max for the GovernorFractional contract.
        voter.weight = bound(_weight, MAX_VOTE_WEIGHT + 1, token.getPastTotalSupply(block.number));

        _mintAndDelegateToVoter(voter);
        uint256 _proposalId = _createAndSubmitProposal();

        uint256 _forVotes;
        uint256 _againstVotes;
        uint256 _abstainVotes;

        if (voteTypeToOverflow[0]) _forVotes = voter.weight;
        if (voteTypeToOverflow[1]) _againstVotes = voter.weight;
        if (voteTypeToOverflow[2]) _abstainVotes = voter.weight;

        bytes memory fractionalizedVotes = abi.encodePacked(_againstVotes, _forVotes, _abstainVotes);
        vm.prank(voter.addr);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, voter.weight));
        governor.castVoteWithReasonAndParams(_proposalId, voter.support, "Weeee", fractionalizedVotes);
    }

    function testFuzz_ParamLengthIsChecked(
        address _voterAddr,
        uint256 _weight,
        FractionalVoteSplit memory _voteSplit,
        bytes memory _invalidVoteData
    ) public {
        uint256 _invalidParamLength = _invalidVoteData.length;
        vm.assume(_invalidParamLength > 0 && _invalidParamLength != 48);

        Voter memory voter;
        voter.weight = bound(_weight, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        voter.voteSplit = _randomVoteSplit(_voteSplit);
        voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);

        _mintAndDelegateToVoter(voter);
        uint256 _proposalId = _createAndSubmitProposal();

        vm.prank(voter.addr);
        vm.expectRevert(Errors.GovernorCountingFractionalInvalidVoteData.selector);
        governor.castVoteWithReasonAndParams(_proposalId, voter.support, "Weeee", _invalidVoteData);
    }

    function test_QuorumDoesIncludeAbstainVotes(address _voterAddr) public {
        uint256 _weight = _getQuorum();
        FractionalVoteSplit memory _voteSplit;
        _voteSplit.percentAbstain = 1e18; // All votes go to ABSTAIN.
        bool _quorumShouldBeReached = true;

        _quorumTest(_voterAddr, _weight, _voteSplit, _quorumShouldBeReached);
    }

    function test_QuorumDoesIncludeForVotes(address _voterAddr) public {
        uint256 _weight = _getQuorum();
        FractionalVoteSplit memory _voteSplit;
        _voteSplit.percentFor = 1e18; // All votes go to FOR.
        bool _quorumShouldBeReached = true;

        _quorumTest(_voterAddr, _weight, _voteSplit, _quorumShouldBeReached);
    }

    function test_QuorumDoesNotIncludeAgainstVotes(address _voterAddr) public {
        uint256 _weight = _getQuorum();
        FractionalVoteSplit memory _voteSplit;
        _voteSplit.percentAgainst = 1e18; // All votes go to AGAINST.
        bool _quorumShouldNotBeReached = false;

        _quorumTest(_voterAddr, _weight, _voteSplit, _quorumShouldNotBeReached);
    }

    function testFuzz_Quorum(address _voterAddr, uint256 _weight, FractionalVoteSplit memory _voteSplit) public {
        uint256 _quorum = _getQuorum();
        _weight = bound(_weight, _quorum, MAX_VOTE_WEIGHT);
        _voteSplit = _randomVoteSplit(_voteSplit);

        uint128 _forVotes = uint128(_weight.mulWadDown(_voteSplit.percentFor));
        uint128 _abstainVotes = uint128(_weight.mulWadDown(_voteSplit.percentAbstain));

        bool _wasQuorumReached = _forVotes + _abstainVotes >= _quorum;
        _quorumTest(_voterAddr, _weight, _voteSplit, _wasQuorumReached);
    }

    function _decodePackedVotes(
        bytes memory voteData
    ) internal pure returns (uint128 againstVotes, uint128 forVotes, uint128 abstainVotes) {
        assembly {
            againstVotes := shr(128, mload(add(voteData, 0x20)))
            forVotes := and(0xffffffffffffffffffffffffffffffff, mload(add(voteData, 0x20)))
            abstainVotes := shr(128, mload(add(voteData, 0x40)))
        }
    }

    function _quorumTest(
        address _voterAddr,
        uint256 _weight,
        FractionalVoteSplit memory _voteSplit,
        bool _isQuorumExpected
    ) internal {
        // Build the voter.
        Voter memory _voter;
        _voter.weight = _weight;
        _voter.voteSplit = _voteSplit;
        _voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);

        // Mint, delegate, and propose.
        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();
        assertEq(_quorumReached(_proposalId), false);

        // Cast votes.
        bytes memory fractionalizedVotes = abi.encodePacked(
            uint128(_voter.weight.mulWadDown(_voteSplit.percentAgainst)),
            uint128(_voter.weight.mulWadDown(_voteSplit.percentFor)),
            uint128(_voter.weight.mulWadDown(_voteSplit.percentAbstain))
        );

        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Idaho", fractionalizedVotes);
        assertEq(_quorumReached(_proposalId), _isQuorumExpected);
    }

    function testFuzz_CanCastWithPartialWeight(
        address _voterAddr,
        uint256 _salt,
        FractionalVoteSplit memory _voteSplit
    ) public {
        // Build a partial weight vote split.
        _voteSplit = _randomVoteSplit(_voteSplit);
        uint256 _percentKeep = bound(_salt, 0.9e18, 0.99e18); // 90% to 99%
        _voteSplit.percentFor = _voteSplit.percentFor.mulWadDown(_percentKeep);
        _voteSplit.percentAgainst = _voteSplit.percentAgainst.mulWadDown(_percentKeep);
        _voteSplit.percentAbstain = _voteSplit.percentAbstain.mulWadDown(_percentKeep);
        assertGt(1e18, _voteSplit.percentFor + _voteSplit.percentAgainst + _voteSplit.percentAbstain);

        // Build the voter.
        Voter memory _voter;
        _voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);
        _voter.weight = bound(_salt, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        _voter.voteSplit = _voteSplit;

        // Mint, delegate, and propose.
        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();
        assertEq(governor.voteWeightCast(_proposalId, _voter.addr), 0);

        // The important thing is just that the abstain votes *cannot* be inferred from
        // the for-votes and against-votes, e.g. by subtracting them from the total weight.
        uint128 _forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor));
        uint128 _againstVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentAgainst));
        uint128 _abstainVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentAbstain));
        assertGt(_voter.weight - _forVotes - _againstVotes, _abstainVotes);

        // Cast votes.
        bytes memory fractionalizedVotes = abi.encodePacked(_againstVotes, _forVotes, _abstainVotes);
        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Lobster", fractionalizedVotes);

        (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) = governor.proposalVotes(
            _proposalId
        );
        assertEq(_forVotes, _actualForVotes);
        assertEq(_againstVotes, _actualAgainstVotes);
        assertEq(_abstainVotes, _actualAbstainVotes);
        assertEq(governor.voteWeightCast(_proposalId, _voter.addr), _forVotes + _againstVotes + _abstainVotes);
    }

    function test_CanCastPartialWeightMultipleTimesAddingToFullWeight() public {
        testFuzz_CanCastPartialWeightMultipleTimes(
            _randomAddress(),
            42 ether,
            0.45e18,
            0.25e18,
            0.3e18,
            FractionalVoteSplit(0.33e18, 0.33e18, 0.34e18)
        );
    }

    function testFuzz_CanCastPartialWeightMultipleTimes(
        address _voterAddr,
        uint256 _weight,
        uint256 _votePercentage1,
        uint256 _votePercentage2,
        uint256 _votePercentage3,
        FractionalVoteSplit memory _voteSplit
    ) public {
        // Build the vote split.
        _voteSplit = _randomVoteSplit(_voteSplit);

        // These are the percentages of the total weight that will be cast with each
        // sequential vote, i.e. if _votePercentage1 is 25% then the first vote will
        // cast 25% of the voter's weight.
        _votePercentage1 = bound(_votePercentage1, 0.0e18, 1.0e18);
        _votePercentage2 = bound(_votePercentage2, 0.0e18, 1e18 - _votePercentage1);
        _votePercentage3 = bound(_votePercentage3, 0.0e18, 1e18 - _votePercentage1 - _votePercentage2);

        // Build the voter.
        Voter memory _voter;
        _voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);
        _voter.weight = bound(_weight, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        _voter.voteSplit = _voteSplit;

        // Mint, delegate, and propose.
        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();
        assertEq(governor.voteWeightCast(_proposalId, _voter.addr), 0);

        // Calculate the vote amounts for the first vote.
        VoteData memory _firstVote;
        _firstVote.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage1));
        _firstVote.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage1)
        );
        _firstVote.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage1)
        );

        // Cast votes the first time.
        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 1st vote",
            abi.encodePacked(_firstVote.againstVotes, _firstVote.forVotes, _firstVote.abstainVotes)
        );

        (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) = governor.proposalVotes(
            _proposalId
        );
        assertEq(_firstVote.forVotes, _actualForVotes);
        assertEq(_firstVote.againstVotes, _actualAgainstVotes);
        assertEq(_firstVote.abstainVotes, _actualAbstainVotes);
        assertEq(
            governor.voteWeightCast(_proposalId, _voter.addr),
            _firstVote.againstVotes + _firstVote.forVotes + _firstVote.abstainVotes
        );

        // If the entire weight was cast; further votes are not possible.
        if (_voter.weight == governor.voteWeightCast(_proposalId, _voter.addr)) return;

        // Now cast votes again.
        VoteData memory _secondVote;
        _secondVote.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage2));
        _secondVote.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage2)
        );
        _secondVote.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage2)
        );

        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 2nd vote",
            abi.encodePacked(_secondVote.againstVotes, _secondVote.forVotes, _secondVote.abstainVotes)
        );

        (_actualAgainstVotes, _actualForVotes, _actualAbstainVotes) = governor.proposalVotes(_proposalId);
        assertEq(_firstVote.forVotes + _secondVote.forVotes, _actualForVotes);
        assertEq(_firstVote.againstVotes + _secondVote.againstVotes, _actualAgainstVotes);
        assertEq(_firstVote.abstainVotes + _secondVote.abstainVotes, _actualAbstainVotes);
        assertEq(
            governor.voteWeightCast(_proposalId, _voter.addr),
            _firstVote.againstVotes +
                _firstVote.forVotes +
                _firstVote.abstainVotes +
                _secondVote.againstVotes +
                _secondVote.forVotes +
                _secondVote.abstainVotes
        );

        // If the entire weight was cast; further votes are not possible.
        if (_voter.weight == governor.voteWeightCast(_proposalId, _voter.addr)) return;

        // Once more unto the breach!
        VoteData memory _thirdVote;
        _thirdVote.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage3));
        _thirdVote.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage3)
        );
        _thirdVote.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage3)
        );

        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 3rd vote",
            abi.encodePacked(_thirdVote.againstVotes, _thirdVote.forVotes, _thirdVote.abstainVotes)
        );

        (_actualAgainstVotes, _actualForVotes, _actualAbstainVotes) = governor.proposalVotes(_proposalId);
        assertEq(_firstVote.forVotes + _secondVote.forVotes + _thirdVote.forVotes, _actualForVotes);
        assertEq(_firstVote.againstVotes + _secondVote.againstVotes + _thirdVote.againstVotes, _actualAgainstVotes);
        assertEq(_firstVote.abstainVotes + _secondVote.abstainVotes + _thirdVote.abstainVotes, _actualAbstainVotes);
        assertEq(
            governor.voteWeightCast(_proposalId, _voter.addr),
            _firstVote.againstVotes +
                _firstVote.forVotes +
                _firstVote.abstainVotes +
                _secondVote.againstVotes +
                _secondVote.forVotes +
                _secondVote.abstainVotes +
                _thirdVote.againstVotes +
                _thirdVote.forVotes +
                _thirdVote.abstainVotes
        );
    }

    // This is a concrete version of the fuzz test above to manually go through
    // all of the calculations at least once.
    function test_CanCastPartialWeightMultipleTimesWithConcreteValues() public {
        // Build the voter.
        Voter memory _voter;
        _voter.addr = _randomAddress();
        _voter.weight = 100 ether;
        _voter.voteSplit = FractionalVoteSplit(
            0.8e18, // 80% for the proposal.
            0.15e18, // 15% against the proposal.
            0.05e18 // 5% abstain.
        );
        FractionalVoteSplit memory _voteSplit = _voter.voteSplit;

        // These are the percentages of the total weight that will be cast with each
        // sequential vote, i.e. if _votePercentage1 is 20% then the first vote will
        // cast 20% of the voter's weight.
        uint256 _votePercentage1 = 0.2e18;
        uint256 _votePercentage2 = 0.5e18;
        uint256 _votePercentage3 = 0.3e18;

        // Mint, delegate, and propose.
        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();

        // Calculate the vote amounts for the first vote.
        VoteData memory _firstVote;
        _firstVote.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage1));
        _firstVote.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage1)
        );
        _firstVote.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage1)
        );

        // Cast votes the first time.
        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 1st vote",
            abi.encodePacked(_firstVote.againstVotes, _firstVote.forVotes, _firstVote.abstainVotes)
        );

        (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) = governor.proposalVotes(
            _proposalId
        );
        assertEq(_actualForVotes, 16 ether); // 100 * 20% * 80%
        assertEq(_actualAgainstVotes, 3 ether); // 100 * 20% * 15%
        assertEq(_actualAbstainVotes, 1 ether); // 100 * 20% * 5%

        // Now cast votes again.
        VoteData memory _secondVote;
        _secondVote.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage2));
        _secondVote.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage2)
        );
        _secondVote.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage2)
        );

        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 2nd vote",
            abi.encodePacked(_secondVote.againstVotes, _secondVote.forVotes, _secondVote.abstainVotes)
        );

        (_actualAgainstVotes, _actualForVotes, _actualAbstainVotes) = governor.proposalVotes(_proposalId);
        assertEq(_actualForVotes, 56 ether); // 16 + 100 * 50% * 80%
        assertEq(_actualAgainstVotes, 10.5 ether); // 3  + 100 * 50% * 15%
        assertEq(_actualAbstainVotes, 3.5 ether); // 1  + 100 * 50% * 5%

        // One more time!
        VoteData memory _thirdVote;
        _thirdVote.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage3));
        _thirdVote.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage3)
        );
        _thirdVote.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage3)
        );

        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 3rd vote",
            abi.encodePacked(_thirdVote.againstVotes, _thirdVote.forVotes, _thirdVote.abstainVotes)
        );

        (_actualAgainstVotes, _actualForVotes, _actualAbstainVotes) = governor.proposalVotes(_proposalId);
        assertEq(_actualForVotes, 80 ether); // 56   + 100 * 30% * 80%
        assertEq(_actualAgainstVotes, 15 ether); // 10.5 + 100 * 30% * 15%
        assertEq(_actualAbstainVotes, 5 ether); // 3.5  + 100 * 30% * 5%

        // All votes should have been cast at this point.
        assertEq(_actualAgainstVotes + _actualForVotes + _actualAbstainVotes, 100 ether);
    }

    function testFuzz_FractionalVotingCannotExceedOverallWeightWithMultipleVotes(
        address _voterAddr,
        uint256 _weight,
        uint256 _votePercentage,
        FractionalVoteSplit memory _voteSplit
    ) public {
        // Build the vote split.
        _voteSplit = _randomVoteSplit(_voteSplit);

        // This needs to be big enough that two votes will exceed the full weight but not so big that
        // one vote exceeds the weight. So it's 51-99%.
        _votePercentage = bound(_votePercentage, 0.51e18, 0.99e18);

        // Build the voter.
        Voter memory _voter;
        _voter.weight = bound(_weight, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        _voter.voteSplit = _voteSplit;
        _voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);

        // Mint, delegate, and propose.
        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();

        // Calculate the vote amounts for the first vote.
        VoteData memory _voteData;
        _voteData.forVotes = uint128(_voter.weight.mulWadDown(_voteSplit.percentFor).mulWadDown(_votePercentage));
        _voteData.againstVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAgainst).mulWadDown(_votePercentage)
        );
        _voteData.abstainVotes = uint128(
            _voter.weight.mulWadDown(_voteSplit.percentAbstain).mulWadDown(_votePercentage)
        );

        // We're going to do this twice to try to exceed our vote weight.
        assertLt(_voter.weight, 2 * (uint256(_voteData.forVotes) + _voteData.againstVotes + _voteData.abstainVotes));

        // Cast votes the first time.
        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 1st vote",
            abi.encodePacked(_voteData.againstVotes, _voteData.forVotes, _voteData.abstainVotes)
        );

        (uint256 _actualAgainstVotes, uint256 _actualForVotes, uint256 _actualAbstainVotes) = governor.proposalVotes(
            _proposalId
        );
        assertEq(_voteData.forVotes, _actualForVotes);
        assertEq(_voteData.againstVotes, _actualAgainstVotes);
        assertEq(_voteData.abstainVotes, _actualAbstainVotes);

        // Attempt to cast votes again. This should revert.
        vm.prank(_voter.addr);
        vm.expectRevert(Errors.GovernorCountingFractionalVoteExceedWeight.selector);
        governor.castVoteWithReasonAndParams(
            _proposalId,
            _voter.support,
            "My 2nd vote",
            abi.encodePacked(_voteData.againstVotes, _voteData.forVotes, _voteData.abstainVotes)
        );
    }

    function testFuzz_NominalVotingCannotExceedOverallWeightWithMultipleVotes(uint256[4] memory _weights) public {
        Voter memory _voter = _setupNominalVoters(_weights)[0];
        _mintAndDelegateToVoter(_voter);

        uint256 _proposalId = _createAndSubmitProposal();
        bytes memory _emptyDataBecauseWereVotingNominally;

        vm.expectEmit(true, true, true, true);
        emit VoteCast(_voter.addr, _proposalId, _voter.support, _voter.weight, "Yay");
        vm.prank(_voter.addr);
        governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Yay", _emptyDataBecauseWereVotingNominally);

        // It should not be possible to vote again.
        vm.prank(_voter.addr);
        vm.expectRevert(Errors.GovernorCountingFractionalAllWeightCast.selector);
        governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Yay", _emptyDataBecauseWereVotingNominally);
    }

    function testFuzz_VotersCannotAvoidWeightChecksByMixedFractionalAndNominalVotes(
        address _voterAddr,
        uint256 _weight,
        FractionalVoteSplit memory _voteSplit,
        uint256 _supportType,
        uint256 _partialVotePrcnt,
        bool _isCastingNominallyFirst
    ) public {
        Voter memory _voter;
        _voter.addr = _assumeAndLabelFuzzedVoter(_voterAddr);
        _voter.weight = bound(_weight, MIN_VOTE_WEIGHT, MAX_VOTE_WEIGHT);
        _voter.voteSplit = _randomVoteSplit(_voteSplit);
        _voter.support = _randomSupportType(_supportType);

        _partialVotePrcnt = bound(_partialVotePrcnt, 0.1e18, 0.99e18); // 10% to 99%
        _voteSplit.percentFor = _voter.voteSplit.percentFor.mulWadDown(_partialVotePrcnt);
        _voteSplit.percentAgainst = _voter.voteSplit.percentAgainst.mulWadDown(_partialVotePrcnt);
        _voteSplit.percentAbstain = _voter.voteSplit.percentAbstain.mulWadDown(_partialVotePrcnt);

        // Build data for both types of vote.
        bytes memory _nominalVoteData;
        bytes memory _fractionalizedVoteData = abi.encodePacked(
            uint128(_voter.weight.mulWadDown(_voteSplit.percentAgainst)), // againstVotes
            uint128(_voter.weight.mulWadDown(_voteSplit.percentFor)), // forVotes
            uint128(_voter.weight.mulWadDown(_voteSplit.percentAbstain)) // abstainVotes
        );

        // Mint, delegate, and propose.
        _mintAndDelegateToVoter(_voter);
        uint256 _proposalId = _createAndSubmitProposal();

        if (_isCastingNominallyFirst) {
            // Vote nominally. It should succeed.
            vm.expectEmit(true, true, true, true);
            emit VoteCast(_voter.addr, _proposalId, _voter.support, _voter.weight, "Nominal vote");
            vm.prank(_voter.addr);
            governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Nominal vote", _nominalVoteData);

            // Now attempt to vote fractionally. It should fail.
            vm.expectRevert(Errors.GovernorCountingFractionalAllWeightCast.selector);
            vm.prank(_voter.addr);
            governor.castVoteWithReasonAndParams(
                _proposalId,
                _voter.support,
                "Fractional vote",
                _fractionalizedVoteData
            );
        } else {
            vm.expectEmit(true, true, true, true);
            emit VoteCastWithParams(
                _voter.addr,
                _proposalId,
                _voter.support,
                _voter.weight,
                "Fractional vote",
                _fractionalizedVoteData
            );
            vm.prank(_voter.addr);
            governor.castVoteWithReasonAndParams(
                _proposalId,
                _voter.support,
                "Fractional vote",
                _fractionalizedVoteData
            );

            vm.prank(_voter.addr);
            vm.expectRevert(Errors.GovernorCountingFractionalVoteWouldExceedWeight.selector);
            governor.castVoteWithReasonAndParams(_proposalId, _voter.support, "Nominal vote", _nominalVoteData);
        }

        // The voter should not have been able to increase his/her vote weight by voting twice.
        (uint256 _againstVotesCast, uint256 _forVotesCast, uint256 _abstainVotesCast) = governor.proposalVotes(
            _proposalId
        );
        assertLe(_againstVotesCast + _forVotesCast + _abstainVotesCast, _voter.weight);
    }
}
