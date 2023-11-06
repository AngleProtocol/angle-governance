// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import { ECDSA } from "oz/utils/cryptography/ECDSA.sol";
import { EIP712 } from "oz/utils/cryptography/EIP712.sol";
import { Math } from "oz/utils/math/Math.sol";
import { SafeCast } from "oz/utils/math/SafeCast.sol";
import { IERC5805 } from "oz/interfaces/IERC5805.sol";
import { IveANGLE } from "./interfaces/IVeANGLE.sol";
import { IveANGLEVotingDelegation } from "./interfaces/IveANGLEVotingDelegation.sol";

/// @title VeANGLEVotingDelegation
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice Fork from Frax Finance: https://github.com/FraxFinance/frax-governance/blob/e465513ac282aa7bfd6744b3136354fae51fed3c/src/veANGLEVotingDelegation.sol
/// @notice Contract that keeps track of voting weights and delegations, leveraging veANGLE
contract VeANGLEVotingDelegation is EIP712, IERC5805 {
    using SafeCast for uint256;

    /// @notice A week
    uint256 public constant WEEK = 7 days;

    /// @notice Max veANGLE lock duration
    uint256 public constant MAX_LOCK_DURATION = 365 days * 4;

    /// @notice vote weight multiplier taken from veANGLE
    /// TODO: update to our case
    uint256 public constant VOTE_WEIGHT_MULTIPLIER = 3;

    /// @notice Typehash needed for delegations by signature
    /// @dev keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)")
    bytes32 public constant DELEGATION_TYPEHASH = 0xe48329057bfd03d55e49b547132e39cffd9c1820ad7b9d4c5307691425d15adf;

    /// @notice veANGLE contract
    IveANGLE public immutable VE_ANGLE;

    /// @notice Nonces needed for delegations by signature
    mapping(address signer => uint256 nonce) public $nonces;

    /// @notice Mapping from delegator to delegate including additional parameters for our weight calculations.
    mapping(address delegator => IveANGLEVotingDelegation.Delegation delegate) public $delegations;

    /// @notice Mapping from delegate to their checkpoints. Checkpoints correspond to daily rounded dates of delegation.
    mapping(address delegate => IveANGLEVotingDelegation.DelegateCheckpoint[]) public $delegateCheckpoints;

    /// @notice Mapping from delegate to weekly rounded time of expiry to the aggregated values at time of expiration. Mirrors veANGLE expiration.
    mapping(address delegate => mapping(uint256 week => IveANGLEVotingDelegation.Expiration))
        public $expiredDelegations;

    /// @notice The ```constructor``` function is called on deployment
    /// @param veANGLE Address of veANGLE contract
    constructor(address veANGLE, string memory name, string memory version) EIP712(name, version) {
        VE_ANGLE = IveANGLE(veANGLE);
    }

    /// @notice The ```getCheckpoint``` function is called to retrieve a specific delegation checkpoint
    /// @dev Get the checkpoint for a delegate at a given index.
    /// @param delegateAddress Address of delegate
    /// @param index Integer index of the checkpoint
    /// @return delegateCheckpoint DelegateCheckpoint of ```delegate``` at ```index```
    function getCheckpoint(
        address delegateAddress,
        uint32 index
    ) external view returns (IveANGLEVotingDelegation.DelegateCheckpoint memory) {
        return $delegateCheckpoints[delegateAddress][index];
    }

    /// @notice The ```_calculateDelegatedWeight``` function calculates weight delegated to ```account``` accounting for any weight that expired since the nearest checkpoint
    /// @dev May include own weight if account previously delegated to someone else and then back to themselves
    /// @param voter Address of voter
    /// @param timestamp A block.timestamp, typically corresponding to a proposal snapshot
    /// @return delegatedWeight Voting weight corresponding to all ```delegateAccount```'s received delegations
    function _calculateDelegatedWeight(
        address voter,
        uint256 timestamp
    ) internal view returns (uint256 delegatedWeight) {
        // Check if delegate account has any delegations
        IveANGLEVotingDelegation.DelegateCheckpoint memory checkpoint = _checkpointBinarySearch({
            _$checkpoints: $delegateCheckpoints[voter],
            timestamp: timestamp
        });

        // If checkpoint is empty, short circuit and return 0 delegated weight
        if (checkpoint.timestamp == 0) {
            return 0;
        }

        // It's possible that some delegated veANGLE has expired.
        // Add up all expirations during this time period, week by week.
        (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredAngle) = _calculateExpirations({
            account: voter,
            start: checkpoint.timestamp,
            end: timestamp,
            checkpoint: checkpoint
        });

        uint256 expirationAdjustedBias = checkpoint.normalizedBias - totalExpiredBias;
        uint256 expirationAdjustedSlope = checkpoint.normalizedSlope - totalExpiredSlope;
        uint256 expirationAdjustedAngle = checkpoint.totalAngle - totalExpiredAngle;

        uint256 voteDecay = expirationAdjustedSlope * timestamp;
        uint256 biasAtTimestamp = (expirationAdjustedBias > voteDecay) ? expirationAdjustedBias - voteDecay : 0;

        // If all delegations are expired they have no voting weight. This differs from veANGLE, which returns the locked ANGLE amount if it has not yet been withdrawn.
        delegatedWeight = expirationAdjustedAngle + (VOTE_WEIGHT_MULTIPLIER * biasAtTimestamp);
    }

    /// @notice The ```_calculateVotingWeight``` function calculates ```account```'s voting weight. Is 0 if they ever delegated and the delegation is in effect.
    /// @param voter Address of voter
    /// @param timestamp A block.timestamp, typically corresponding to a proposal snapshot
    /// @return votingWeight Voting weight corresponding to ```account```'s veANGLE balance
    function _calculateVotingWeight(address voter, uint256 timestamp) internal view returns (uint256) {
        // If lock is expired they have no voting weight. This differs from veANGLE, which returns the locked ANGLE amount if it has not yet been withdrawn.
        if (VE_ANGLE.locked(voter).end <= timestamp) return 0;

        uint256 firstDelegationTimestamp = $delegations[voter].firstDelegationTimestamp;
        // Never delegated OR this timestamp is before the first delegation by account
        if (firstDelegationTimestamp == 0 || timestamp < firstDelegationTimestamp) {
            try VE_ANGLE.balanceOf({ addr: voter, _t: timestamp }) returns (uint256 _balance) {
                return _balance;
            } catch {}
        }
        return 0;
    }

    /// @notice The ```calculateExpirations``` function calculates all expired delegations for an account since the last checkpoint.
    /// @dev Can be used in tandem with writeNewCheckpointForExpirations() to write a new checkpoint
    /// @dev Long time periods between checkpoints can increase gas costs for delegate() and castVote()
    /// @dev See _calculateExpirations
    /// @param delegateAddress Address of delegate
    /// @return calculatedCheckpoint A new DelegateCheckpoint to write based on expirations since previous checkpoint
    function calculateExpiredDelegations(
        address delegateAddress
    ) public view returns (IveANGLEVotingDelegation.DelegateCheckpoint memory calculatedCheckpoint) {
        IveANGLEVotingDelegation.DelegateCheckpoint[] storage $userDelegationCheckpoints = $delegateCheckpoints[
            delegateAddress
        ];

        // This ensures that checkpoints take effect at the next epoch
        uint256 checkpointTimestamp = ((block.timestamp / 1 days) * 1 days) + 1 days;
        uint256 checkpointsLength = $userDelegationCheckpoints.length;

        // Nothing to expire if no one delegated to you
        if (checkpointsLength == 0) return calculatedCheckpoint;

        IveANGLEVotingDelegation.DelegateCheckpoint memory lastCheckpoint = $userDelegationCheckpoints[
            checkpointsLength - 1
        ];

        // Nothing expired because the most recent checkpoint is already written
        if (lastCheckpoint.timestamp == checkpointTimestamp) {
            return calculatedCheckpoint;
        }

        (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredAngle) = _calculateExpirations({
            account: delegateAddress,
            start: lastCheckpoint.timestamp,
            end: checkpointTimestamp,
            checkpoint: lastCheckpoint
        });

        // All will be 0 if no expirations, only need to check one of them
        if (totalExpiredAngle == 0) return calculatedCheckpoint;

        /// NOTE: Checkpoint values will always be larger than or equal to expired values
        unchecked {
            calculatedCheckpoint = IveANGLEVotingDelegation.DelegateCheckpoint({
                timestamp: uint128(checkpointTimestamp),
                normalizedBias: uint128(lastCheckpoint.normalizedBias - totalExpiredBias),
                normalizedSlope: uint128(lastCheckpoint.normalizedSlope - totalExpiredSlope),
                totalAngle: uint128(lastCheckpoint.totalAngle - totalExpiredAngle)
            });
        }
    }

    /// @notice The ```writeNewCheckpointForExpirations``` function writes a new checkpoint if any weight has expired since the previous checkpoint
    /// @dev Long time periods between checkpoints can increase gas costs for delegate() and castVote()
    /// @dev See _calculateExpirations
    /// @param delegateAddress Address of delegate
    function writeNewCheckpointForExpiredDelegations(address delegateAddress) external {
        IveANGLEVotingDelegation.DelegateCheckpoint memory newCheckpoint = calculateExpiredDelegations(delegateAddress);

        if (newCheckpoint.timestamp == 0) revert IveANGLEVotingDelegation.NoExpirations();

        $delegateCheckpoints[delegateAddress].push(newCheckpoint);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice The ```_getVotingWeight``` function calculates a voter's voting weight at ```timestamp```
    /// @param voter Address of voter
    /// @param timestamp A block.timestamp, typically corresponding to a proposal snapshot
    /// @return totalVotingWeight Voting weight of ```voter``` at ```timestamp```
    function _getVotingWeight(address voter, uint256 timestamp) internal view returns (uint256 totalVotingWeight) {
        totalVotingWeight =
            _calculateVotingWeight({ voter: voter, timestamp: timestamp }) +
            _calculateDelegatedWeight({ voter: voter, timestamp: timestamp });
    }

    /// @notice The ```getVotes``` function calculates a voter's weight at ```timestamp```
    /// @param voter Address of voter
    /// @param timepoint A block.timestamp, typically corresponding to a proposal snapshot
    /// @return votingWeight Voting weight of ```voterAddress``` at ```timepoint```
    function getVotes(address voter, uint256 timepoint) external view returns (uint256) {
        return _getVotingWeight({ voter: voter, timestamp: timepoint });
    }

    /// @notice The ```getVotes``` function calculates a voter's weight at the current block.timestamp
    /// @param voter Address of voter
    /// @return votingWeight Voting weight of ```voterAddress``` at ```block.timestamp```
    function getVotes(address voter) external view returns (uint256 votingWeight) {
        votingWeight = _getVotingWeight({ voter: voter, timestamp: block.timestamp });
    }

    /// @notice The ```getPastVotes``` function calculates a voter's weight at ```timepoint```
    /// @param voter Address of voter
    /// @param timepoint A block.timestamp, typically corresponding to a proposal snapshot, must be in past
    /// @return pastVotingWeight Voting weight of ```account``` at ```timepoint``` in past
    function getPastVotes(address voter, uint256 timepoint) external view returns (uint256 pastVotingWeight) {
        if (timepoint >= block.timestamp) revert IveANGLEVotingDelegation.TimestampInFuture();

        pastVotingWeight = _getVotingWeight({ voter: voter, timestamp: timepoint });
    }

    /// @notice The ```getPastTotalSupply``` function retrieves the total supply of veANGLE at ```blockNumber```
    /// @dev Must use block.number instead of timestamp because VE_ANGLE.totalSupply(timestamp) doesn't work for historical values.
    /// @param blockNumber block.number of total supply, must be in past
    /// @return pastTotalSupply veANGLE supply at ```blockNumber```
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256 pastTotalSupply) {
        // Future blocks are not valid
        if (blockNumber >= block.number) revert IveANGLEVotingDelegation.BlockNumberInFuture();

        // Our total voting weight isn't the same as VE_ANGLE.totalSupplyAt(blockNumber) because
        // we expire all voting weight when the lock ends, which also may not be accounted for yet.
        // This is close enough.
        pastTotalSupply = VE_ANGLE.totalSupplyAt(blockNumber);
    }

    /// @notice The ```delegates``` function returns who the address of the delegate, that delegatorAddress has chosen
    /// @param delegator Address of delegator
    /// @return delegateAddress Address of the delegate
    function delegates(address delegator) external view returns (address delegateAddress) {
        delegateAddress = $delegations[delegator].delegate;
    }

    /// @notice The ```delegate``` function delegates votes from signer to ```delegatee``` at the next epoch
    /// @param delegatee Address to delegate to
    function delegate(address delegatee) external {
        _delegate({ delegator: msg.sender, delegatee: delegatee });
    }

    /// @notice The ```delegate``` function delegates votes from signer to ```delegatee```
    /// @param delegatee Address to delegate to
    /// @param nonce Nonce of signed message
    /// @param expiry Expiry time of message
    /// @param v Recovery ID
    /// @param r Output of an ECDSA signature
    /// @param s Output of an ECDSA signature
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        // Revert if signature is expired
        if (block.timestamp > expiry) revert IveANGLEVotingDelegation.SignatureExpired();

        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );

        // Increment nonce and check against incremented value
        if (nonce != $nonces[signer]++) revert IveANGLEVotingDelegation.InvalidSignatureNonce();
        _delegate(signer, delegatee);
    }

    /// @notice The ```_delegate``` function delegates votes from signer to ```delegatee``` at the next epoch
    /// @param delegator Caller delegating their weight
    /// @param delegatee Address to delegate to
    /// @dev An account can only delegate to one account at a time. The previous delegation will be overwritten.
    /// @dev To undelegate, ```delegatee``` should be ```address(delegator)```
    function _delegate(address delegator, address delegatee) internal {
        // Revert if delegating to self with address(0), should be address(delegator)
        if (delegatee == address(0)) revert IveANGLEVotingDelegation.IncorrectSelfDelegation();

        IveANGLEVotingDelegation.Delegation memory previousDelegation = $delegations[delegator];

        // This ensures that checkpoints take effect at the next epoch
        uint256 checkpointTimestamp = ((block.timestamp / 1 days) * 1 days) + 1 days;

        IveANGLEVotingDelegation.NormalizedVeANGLELockInfo
            memory normalizedDelegatorVeANGLELockInfo = _getNormalizedveANGLELockInfo({
                delegator: delegator,
                checkpointTimestamp: checkpointTimestamp
            });

        _moveVotingPowerFromPreviousDelegate({
            previousDelegation: previousDelegation,
            checkpointTimestamp: checkpointTimestamp
        });

        _moveVotingPowerToNewDelegate({
            newDelegate: delegatee,
            delegatorVeANGLELockInfo: normalizedDelegatorVeANGLELockInfo,
            checkpointTimestamp: checkpointTimestamp
        });

        // NOTE: Unsafe casting because these values will never exceed the size of their respective types
        $delegations[delegator] = IveANGLEVotingDelegation.Delegation({
            delegate: delegatee,
            firstDelegationTimestamp: previousDelegation.firstDelegationTimestamp == 0
                ? uint48(checkpointTimestamp)
                : previousDelegation.firstDelegationTimestamp,
            expiry: uint48(normalizedDelegatorVeANGLELockInfo.expiry),
            bias: uint96(normalizedDelegatorVeANGLELockInfo.bias),
            angle: uint96(normalizedDelegatorVeANGLELockInfo.angle),
            slope: uint64(normalizedDelegatorVeANGLELockInfo.slope)
        });

        emit DelegateChanged({
            delegator: delegator,
            fromDelegate: previousDelegation.delegate,
            toDelegate: delegatee
        });
    }

    /// @notice The ```_getNormalizedVeANGLELockInfo``` function retrieves lock information from veANGLE. We normalize and store this information to calculate voting weights
    /// @param delegator Address of the delegator
    /// @param checkpointTimestamp block.timestamp of the next checkpoint epoch
    /// @return normalizedVeANGLELockInfo Information about delegator's lock from veANGLE contract, normalized
    function _getNormalizedveANGLELockInfo(
        address delegator,
        uint256 checkpointTimestamp
    ) private view returns (IveANGLEVotingDelegation.NormalizedVeANGLELockInfo memory normalizedVeANGLELockInfo) {
        // Check expiry in case we need to revert
        uint256 expiry = VE_ANGLE.locked(delegator).end;
        if (expiry <= checkpointTimestamp) revert IveANGLEVotingDelegation.CantDelegateLockExpired();

        // Most recent epoch
        uint256 epoch = VE_ANGLE.user_point_epoch(delegator);
        // Values for delegator at the most recent epoch
        (int128 userBias, int128 userSlope, , , uint256 userAngle) = VE_ANGLE.user_point_history({
            _addr: delegator,
            _idx: epoch
        });
        // Get the timestamp of the last update in veANGLE user history
        uint256 lastUpdate = VE_ANGLE.user_point_history__ts({ _addr: delegator, _idx: epoch });

        // Set return values
        normalizedVeANGLELockInfo.slope = SafeCast.toUint256(userSlope);
        normalizedVeANGLELockInfo.angle = userAngle;
        normalizedVeANGLELockInfo.expiry = expiry;
        // Normalize bias to unix epoch, so all biases can be added and subtracted directly
        normalizedVeANGLELockInfo.bias = SafeCast.toUint256(userBias) + normalizedVeANGLELockInfo.slope * lastUpdate;
    }

    /// @notice The ```_checkpointBinarySearch``` function does a binary search for the closest checkpoint before ```timestamp```
    /// @param _$checkpoints Storage pointer to the account's DelegateCheckpoints
    /// @param timestamp block.timestamp to get voting power at, frequently proposal snapshot
    /// @return closestCheckpoint The closest DelegateCheckpoint before timestamp
    function _checkpointBinarySearch(
        IveANGLEVotingDelegation.DelegateCheckpoint[] storage _$checkpoints,
        uint256 timestamp
    ) private view returns (IveANGLEVotingDelegation.DelegateCheckpoint memory closestCheckpoint) {
        uint256 checkpointsLength = _$checkpoints.length;

        // What the newest checkpoint could be for timestamp (rounded to whole days). It will be earlier when checkpoints are sparse.
        uint256 roundedDownTimestamp = (timestamp / 1 days) * 1 days;
        // Newest checkpoint's timestamp (already rounded to whole days)
        uint256 lastCheckpointTimestamp = checkpointsLength > 0 ? _$checkpoints[checkpointsLength - 1].timestamp : 0;
        // The furthest back a checkpoint will ever be is the number of days delta between timestamp and the last
        // checkpoints timestamp. This happens when there was a checkpoint written every single day over that period.
        // If roundedDownTimestamp > lastCheckpointTimestamp that means that we can just use the last index as
        // the checkpoint.
        uint256 delta = lastCheckpointTimestamp > roundedDownTimestamp
            ? (lastCheckpointTimestamp - roundedDownTimestamp) / 1 days
            : 0;
        // low index is equal to the last checkpoints index minus the index delta
        uint256 low = (checkpointsLength > 0 && checkpointsLength - 1 > delta) ? checkpointsLength - 1 - delta : 0;

        uint256 high = checkpointsLength;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_$checkpoints[mid].timestamp > timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        closestCheckpoint = high == 0 ? closestCheckpoint : _$checkpoints[high - 1];
    }

    /// @notice The ```_moveVotingPowerFromPreviousDelegate``` function removes voting power from the previous delegate, handling expirations
    /// @notice and writing a new DelegateCheckpoint
    /// @param previousDelegation The delegator's previous delegation
    /// @param checkpointTimestamp block.timestamp of the next DelegateCheckpoint's epoch
    function _moveVotingPowerFromPreviousDelegate(
        IveANGLEVotingDelegation.Delegation memory previousDelegation,
        uint256 checkpointTimestamp
    ) private {
        // Remove voting power from previous delegate, if they exist
        if (previousDelegation.delegate != address(0)) {
            // Get the last Checkpoint for previous delegate
            IveANGLEVotingDelegation.DelegateCheckpoint[] storage $previousDelegationCheckpoints = $delegateCheckpoints[
                previousDelegation.delegate
            ];
            uint256 accountCheckpointsLength = $previousDelegationCheckpoints.length;
            // NOTE: we know that _accountsCheckpointLength > 0 because we have already checked that the previous delegation exists
            IveANGLEVotingDelegation.DelegateCheckpoint memory lastCheckpoint = $previousDelegationCheckpoints[
                accountCheckpointsLength - 1
            ];
            uint256 oldWeightOldDelegate = _getVotingWeight(previousDelegation.delegate, checkpointTimestamp);

            // Handle Expirations

            // Only subtract when the delegator's expiration is in the future. This way, the former delegates voting power
            // will still properly expire for proposals that happen between previousDelegation.expiry and a new delegation.
            // See testExpiredLockRedelegateNoVotingWeight().
            if (previousDelegation.expiry > checkpointTimestamp) {
                // Calculations
                IveANGLEVotingDelegation.Expiration memory expiration = $expiredDelegations[
                    previousDelegation.delegate
                ][previousDelegation.expiry];
                // All expiration fields will never exceed their size so subtraction doesnt need to be checked
                // and they can be unsafely cast
                unchecked {
                    expiration.bias -= uint96(previousDelegation.bias);
                    expiration.slope -= uint64(previousDelegation.slope);
                    expiration.angle -= uint96(previousDelegation.angle);
                }

                // Effects
                $expiredDelegations[previousDelegation.delegate][previousDelegation.expiry] = expiration;
            }

            {
                // Calculate new checkpoint
                IveANGLEVotingDelegation.DelegateCheckpoint memory newCheckpoint = _calculateCheckpoint({
                    previousCheckpoint: lastCheckpoint,
                    account: previousDelegation.delegate,
                    isDeltaPositive: false,
                    deltaBias: previousDelegation.bias,
                    deltaSlope: previousDelegation.slope,
                    deltaAngle: previousDelegation.angle,
                    checkpointTimestamp: checkpointTimestamp,
                    previousDelegationExpiry: previousDelegation.expiry
                });

                // Write new checkpoint
                _writeCheckpoint({
                    $userDelegationCheckpoints: $previousDelegationCheckpoints,
                    accountCheckpointsLength: accountCheckpointsLength,
                    newCheckpoint: newCheckpoint,
                    lastCheckpoint: lastCheckpoint
                });
            }

            // NOTE: oldWeightOldDelegate has had voting power decay since the previous event, meaning that
            // this event shouldn't be relied on. We did our best to conform to the standard.
            emit DelegateVotesChanged({
                delegate: previousDelegation.delegate,
                previousVotes: oldWeightOldDelegate,
                newVotes: _getVotingWeight({ voter: previousDelegation.delegate, timestamp: checkpointTimestamp })
            });
        }
    }

    /// @notice The ```_moveVotingPowerToNewDelegate``` function adds voting power to the new delegate, handling expirations
    /// @notice and writing a new DelegateCheckpoint
    /// @param newDelegate The new delegate that is being delegated to
    /// @param delegatorVeANGLELockInfo Information about the delegator's veANGLE lock
    /// @param checkpointTimestamp block.timestamp of the next DelegateCheckpoint's epoch
    function _moveVotingPowerToNewDelegate(
        address newDelegate,
        IveANGLEVotingDelegation.NormalizedVeANGLELockInfo memory delegatorVeANGLELockInfo,
        uint256 checkpointTimestamp
    ) private {
        // Get the last checkpoint for the new delegate
        IveANGLEVotingDelegation.DelegateCheckpoint[] storage $newDelegateCheckpoints = $delegateCheckpoints[
            newDelegate
        ];
        uint256 accountCheckpointsLength = $newDelegateCheckpoints.length;
        IveANGLEVotingDelegation.DelegateCheckpoint memory lastCheckpoint = accountCheckpointsLength == 0
            ? IveANGLEVotingDelegation.DelegateCheckpoint(0, 0, 0, 0)
            : $newDelegateCheckpoints[accountCheckpointsLength - 1];
        uint256 oldWeightNewDelegate = _getVotingWeight(newDelegate, checkpointTimestamp);

        // Handle expiration
        // Calculations
        IveANGLEVotingDelegation.Expiration memory expiration = $expiredDelegations[newDelegate][
            delegatorVeANGLELockInfo.expiry
        ];

        // NOTE: All expiration fields will never exceed their size so addition doesnt need to be checked
        // and can be unsafely cast
        unchecked {
            expiration.bias += uint96(delegatorVeANGLELockInfo.bias);
            expiration.slope += uint64(delegatorVeANGLELockInfo.slope);
            expiration.angle += uint96(delegatorVeANGLELockInfo.angle);
        }
        // Effects
        $expiredDelegations[newDelegate][delegatorVeANGLELockInfo.expiry] = expiration;

        // Calculate new checkpoint
        IveANGLEVotingDelegation.DelegateCheckpoint memory newCheckpoint = _calculateCheckpoint({
            previousCheckpoint: lastCheckpoint,
            isDeltaPositive: true,
            account: newDelegate,
            deltaBias: delegatorVeANGLELockInfo.bias,
            deltaSlope: delegatorVeANGLELockInfo.slope,
            deltaAngle: delegatorVeANGLELockInfo.angle,
            checkpointTimestamp: checkpointTimestamp,
            previousDelegationExpiry: 0 // not used
        });

        // Write new checkpoint
        _writeCheckpoint({
            $userDelegationCheckpoints: $newDelegateCheckpoints,
            accountCheckpointsLength: accountCheckpointsLength,
            newCheckpoint: newCheckpoint,
            lastCheckpoint: lastCheckpoint
        });

        // NOTE: oldWeightNewDelegate has had voting power decay since the previous event, meaning that
        // this event shouldn't be relied on. We did our best to conform to the standard.
        emit DelegateVotesChanged({
            delegate: newDelegate,
            previousVotes: oldWeightNewDelegate,
            newVotes: _getVotingWeight({ voter: newDelegate, timestamp: checkpointTimestamp })
        });
    }

    /// @notice The ```_calculateCheckpoint``` function calculates the values to be written for the new DelegateCheckpoint
    /// @param previousCheckpoint The previous checkpoint for account
    /// @param account The account to calculate the expirations for
    /// @param isDeltaPositive Whether adding or subtracting from the previous checkpoint
    /// @param deltaBias Amount of bias to add or subtract
    /// @param deltaSlope Amount of slope to add or subtract
    /// @param deltaAngle Amount of ANGLE to add or subtract
    /// @param checkpointTimestamp block.timestamp of the next DelegateCheckpoint's epoch
    /// @param previousDelegationExpiry When the previous delegation expires
    /// @return newCheckpoint The new DelegateCheckpoint to be stored
    function _calculateCheckpoint(
        IveANGLEVotingDelegation.DelegateCheckpoint memory previousCheckpoint,
        address account,
        bool isDeltaPositive,
        uint256 deltaBias,
        uint256 deltaSlope,
        uint256 deltaAngle,
        uint256 checkpointTimestamp,
        uint256 previousDelegationExpiry
    ) private view returns (IveANGLEVotingDelegation.DelegateCheckpoint memory newCheckpoint) {
        // If this is the first checkpoint, create a new one and early return
        if (previousCheckpoint.timestamp == 0) {
            return
                IveANGLEVotingDelegation.DelegateCheckpoint({
                    // can be unsafely cast because values will never exceed uint128 max
                    timestamp: uint128(checkpointTimestamp),
                    normalizedBias: uint128(deltaBias),
                    normalizedSlope: uint128(deltaSlope),
                    totalAngle: uint128(deltaAngle)
                });
        }

        newCheckpoint.timestamp = previousCheckpoint.timestamp;
        newCheckpoint.normalizedBias = previousCheckpoint.normalizedBias;
        newCheckpoint.normalizedSlope = previousCheckpoint.normalizedSlope;
        newCheckpoint.totalAngle = previousCheckpoint.totalAngle;

        // All checkpoint fields will never exceed their size so addition and subtraction doesnt need to be checked
        unchecked {
            // Add or subtract the delta to the previous checkpoint
            if (isDeltaPositive) {
                newCheckpoint.normalizedBias += uint128(deltaBias);
                newCheckpoint.normalizedSlope += uint128(deltaSlope);
                newCheckpoint.totalAngle += uint128(deltaAngle);
            } else {
                // only subtract the weight from this account if it has not already expired in a previous checkpoint
                if (previousDelegationExpiry > previousCheckpoint.timestamp) {
                    newCheckpoint.normalizedBias -= uint128(deltaBias);
                    newCheckpoint.normalizedSlope -= uint128(deltaSlope);
                    newCheckpoint.totalAngle -= uint128(deltaAngle);
                }
            }

            // If there have been expirations, incorporate the adjustments by subtracting them from the checkpoint
            if (newCheckpoint.timestamp != checkpointTimestamp) {
                (
                    uint256 totalExpiredBias,
                    uint256 totalExpiredSlope,
                    uint256 totalExpiredAngle
                ) = _calculateExpirations({
                        account: account,
                        start: newCheckpoint.timestamp,
                        end: checkpointTimestamp,
                        checkpoint: previousCheckpoint
                    });

                newCheckpoint.timestamp = uint128(checkpointTimestamp);
                newCheckpoint.normalizedBias -= uint128(totalExpiredBias);
                newCheckpoint.normalizedSlope -= uint128(totalExpiredSlope);
                newCheckpoint.totalAngle -= uint128(totalExpiredAngle);
            }
        }
    }

    /// @notice The ```_writeCheckpoint``` function pushes a new checkpoint to the array or updates the most recent one if it already exists for the current epoch
    /// @param $userDelegationCheckpoints Pointer to the user's delegation checkpoints
    /// @param accountCheckpointsLength The length of the user's delegation checkpoints
    /// @param newCheckpoint The new checkpoint returned from _calculateCheckpoint()
    /// @param lastCheckpoint The most recent delegate checkpoint
    function _writeCheckpoint(
        IveANGLEVotingDelegation.DelegateCheckpoint[] storage $userDelegationCheckpoints,
        uint256 accountCheckpointsLength,
        IveANGLEVotingDelegation.DelegateCheckpoint memory newCheckpoint,
        IveANGLEVotingDelegation.DelegateCheckpoint memory lastCheckpoint
    ) internal {
        // If the newCheckpoint has the same timestamp as the last checkpoint, overwrite it
        if (accountCheckpointsLength > 0 && lastCheckpoint.timestamp == newCheckpoint.timestamp) {
            $userDelegationCheckpoints[accountCheckpointsLength - 1] = newCheckpoint;
        } else {
            // Otherwise, push a new checkpoint
            $userDelegationCheckpoints.push(newCheckpoint);
        }
    }

    /// @notice The ```_calculateExpirations``` function generates a summation of all bias, slope, and angle for all delegations that expire during the specified time window for ```account```
    /// @param account Delegate account to generate summations for
    /// @param start Timestamp to start the summations from. The start is not included
    /// @param end Timestamp to end the summations. The end is included
    /// @param checkpoint Checkpoint to start expirations at
    /// @return totalExpiredBias Total bias that expired for delegate ```account``` during timeframe
    /// @return totalExpiredSlope Total slope that expired for delegate ```account``` during timeframe
    /// @return totalExpiredAngle Total ANGLE that expired for delegate ```account``` during timeframe
    function _calculateExpirations(
        address account,
        uint256 start,
        uint256 end,
        IveANGLEVotingDelegation.DelegateCheckpoint memory checkpoint
    ) private view returns (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredAngle) {
        unchecked {
            // Maximum lock time for veANGLE is 4 years, it will all be expired
            if (end > start + MAX_LOCK_DURATION) {
                totalExpiredBias = checkpoint.normalizedBias;
                totalExpiredSlope = checkpoint.normalizedSlope;
                totalExpiredAngle = checkpoint.totalAngle;
            } else {
                // Total values will always be less than or equal to a checkpoint's values
                uint256 currentWeek = WEEK + (start / WEEK) * WEEK;
                mapping(uint256 => IveANGLEVotingDelegation.Expiration)
                    storage $delegateExpirations = $expiredDelegations[account];
                // Sum values from currentWeek until end
                while (currentWeek <= end) {
                    IveANGLEVotingDelegation.Expiration memory expiration = $delegateExpirations[currentWeek];
                    totalExpiredBias += expiration.bias;
                    totalExpiredSlope += expiration.slope;
                    totalExpiredAngle += expiration.angle;
                    currentWeek += WEEK;
                }
            }
        }
    }
}
