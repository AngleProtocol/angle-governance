// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

error GovernorCountingFractionalVoteWouldExceedWeight();
error GovernorCountingFractionalInvalidSupportValueNotVoteType();
error GovernorCountingFractionalInvalidVoteData();
error GovernorCountingFractionalVoteExceedWeight();
error GovernorCountingFractionalNoWeight();
error GovernorCountingFractionalAllWeightCast();
error InvalidTimepoint();
error NotExecutor();
error OmnichainGovernanceExecutorTxExecReverted();
error OmnichainProposalSenderDestinationChainNotTrustedSource();
error OmnichainProposalSenderInvalidEndpoint();
error OmnichainProposalSenderInvalidExecParams();
error OmnichainProposalSenderNoStoredPayload();
error ShortCircuitNumeratorGreaterThanQuorumDenominator();
