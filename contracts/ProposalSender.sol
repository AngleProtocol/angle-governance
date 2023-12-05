// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "oz/access/Ownable.sol";
import "oz/utils/ReentrancyGuard.sol";
import "lz/lzApp/interfaces/ILayerZeroEndpoint.sol";

import "./utils/Errors.sol";

/// @title ProposalSender
/// @author LayerZero Labs
/// @notice Sends a proposal's data to remote chains for execution after the proposal passes on the main chain
/// @dev In Angle setting where there is one Timelock contract per chain to which this proposal sender sends payloads
/// the owner of this contract must be the `Governor` contract itself
/// @dev Full fork from:
/// https://github.com/LayerZero-Labs/omnichain-governance-executor/blob/main/contracts/OmnichainProposalSender.sol
//solhint-disable
/// @dev Acknowledge issue: `setTrustedRemoteAddress`, `setSendVersion` and `setConfig` are not protected by
/// a timelock. But any other proposal will need to be executed through a timelock because the other chains
/// are still dependant on their timelock contract.
contract ProposalSender is Ownable, ReentrancyGuard {
    uint64 public lastStoredPayloadNonce;

    /// @notice Execution hashes of failed messages
    /// @dev [nonce] -> [executionHash]
    mapping(uint64 => bytes32) public storedExecutionHashes;

    /// @notice LayerZero endpoint for sending messages to remote chains
    ILayerZeroEndpoint public immutable lzEndpoint;

    /// @notice Specifies the allowed path for sending messages
    /// (remote chainId => remote app address + local app address)
    mapping(uint16 => bytes) public trustedRemoteLookup;

    /// @notice Emitted when a remote message receiver is set for the remote chain
    event SetTrustedRemoteAddress(uint16 remoteChainId, bytes remoteAddress);

    /// @notice Emitted when a proposal execution request sent to the remote chain
    event ExecuteRemoteProposal(uint16 indexed remoteChainId, bytes payload);

    /// @notice Emitted when a previously failed message successfully sent to the remote chain
    event ClearPayload(uint64 indexed nonce, bytes32 executionHash);

    /// @notice Emitted when an execution hash of a failed message saved
    event StorePayload(
        uint64 indexed nonce,
        uint16 indexed remoteChainId,
        bytes payload,
        bytes adapterParams,
        uint value,
        bytes reason
    );

    constructor(ILayerZeroEndpoint _lzEndpoint) Ownable(msg.sender) {
        if (address(_lzEndpoint) == address(0)) revert OmnichainProposalSenderInvalidEndpoint();
        lzEndpoint = _lzEndpoint;
    }

    /// @notice Estimates LayerZero fees for cross-chain message delivery to the remote chain
    /// @dev The estimated fees are the minimum required, it's recommended to increase the fees
    /// amount when sending a message. The unused amount will be refunded
    /// @param remoteChainId The LayerZero id of a remote chain
    /// @param payload The payload to be sent to the remote chain. It's computed as follows:
    /// payload = abi.encode(targets, values, signatures, calldatas)
    /// @param adapterParams The params used to specify the custom amount of gas required for the execution
    /// on the destination
    /// @return nativeFee The amount of fee in the native gas token (e.g. ETH)
    /// @return zroFee The amount of fee in ZRO token
    function estimateFees(
        uint16 remoteChainId,
        bytes calldata payload,
        bytes calldata adapterParams
    ) external view returns (uint nativeFee, uint zroFee) {
        return lzEndpoint.estimateFees(remoteChainId, address(this), payload, false, adapterParams);
    }

    /// @notice Sends a message to execute a remote proposal
    /// @dev Stores the hash of the execution parameters if sending fails (e.g., due to insufficient fees)
    /// @param remoteChainId The LayerZero id of the remote chain
    /// @param payload The payload to be sent to the remote chain. It's computed as follows:
    /// payload = abi.encode(targets, values, signatures, calldatas)
    /// @param adapterParams The params used to specify the custom amount of gas required for the execution
    /// on the destination
    function execute(
        uint16 remoteChainId,
        bytes calldata payload,
        bytes calldata adapterParams
    ) external payable onlyOwner {
        bytes memory trustedRemote = trustedRemoteLookup[remoteChainId];
        if (trustedRemote.length == 0) revert OmnichainProposalSenderDestinationChainNotTrustedSource();

        try
            lzEndpoint.send{ value: msg.value }(
                remoteChainId,
                trustedRemote,
                payload,
                payable(tx.origin),
                address(0),
                adapterParams
            )
        {
            emit ExecuteRemoteProposal(remoteChainId, payload);
        } catch (bytes memory reason) {
            uint64 _lastStoredPayloadNonce = ++lastStoredPayloadNonce;
            bytes memory execution = abi.encode(remoteChainId, payload, adapterParams, msg.value);
            storedExecutionHashes[_lastStoredPayloadNonce] = keccak256(execution);
            emit StorePayload(_lastStoredPayloadNonce, remoteChainId, payload, adapterParams, msg.value, reason);
        }
    }

    /// @notice Resends a previously failed message
    /// @dev Allows to provide more fees if needed. The extra fees will be refunded to the caller
    /// @param nonce The nonce to identify a failed message
    /// @param remoteChainId The LayerZero id of the remote chain
    /// @param payload The payload to be sent to the remote chain. It's computed as follows:
    /// payload = abi.encode(targets, values, signatures, calldatas)
    /// @param adapterParams The params used to specify the custom amount of gas required for the execution
    /// on the destination
    /// @param originalValue The msg.value passed when execute() function was called
    function retryExecute(
        uint64 nonce,
        uint16 remoteChainId,
        bytes calldata payload,
        bytes calldata adapterParams,
        uint originalValue
    ) external payable nonReentrant {
        bytes32 hash = storedExecutionHashes[nonce];
        if (hash == bytes32(0)) revert OmnichainProposalSenderNoStoredPayload();

        bytes memory execution = abi.encode(remoteChainId, payload, adapterParams, originalValue);
        if (keccak256(execution) != hash) revert OmnichainProposalSenderInvalidExecParams();

        delete storedExecutionHashes[nonce];

        lzEndpoint.send{ value: originalValue + msg.value }(
            remoteChainId,
            trustedRemoteLookup[remoteChainId],
            payload,
            payable(msg.sender),
            address(0),
            adapterParams
        );
        emit ClearPayload(nonce, hash);
    }

    /// @notice Sets the remote message receiver address
    /// @param remoteChainId The LayerZero id of a remote chain
    /// @param remoteAddress The address of the contract on the remote chain to receive messages sent by this contract
    function setTrustedRemoteAddress(uint16 remoteChainId, bytes calldata remoteAddress) external onlyOwner {
        trustedRemoteLookup[remoteChainId] = abi.encodePacked(remoteAddress, address(this));
        emit SetTrustedRemoteAddress(remoteChainId, remoteAddress);
    }

    /// @notice Sets the configuration of the LayerZero messaging library of the specified version
    /// @param version Messaging library version
    /// @param chainId The LayerZero chainId for the pending config change
    /// @param configType The type of configuration. Every messaging library has its own convention
    /// @param config The configuration in bytes. It can encode arbitrary content
    function setConfig(uint16 version, uint16 chainId, uint configType, bytes calldata config) external onlyOwner {
        lzEndpoint.setConfig(version, chainId, configType, config);
    }

    /// @notice Sets the configuration of the LayerZero messaging library of the specified version
    /// @param version New messaging library version
    function setSendVersion(uint16 version) external onlyOwner {
        lzEndpoint.setSendVersion(version);
    }

    /// @notice Gets the configuration of the LayerZero messaging library of the specified version
    /// @param version Messaging library version
    /// @param chainId The LayerZero chainId
    /// @param configType Type of configuration. Every messaging library has its own convention.
    function getConfig(uint16 version, uint16 chainId, uint configType) external view returns (bytes memory) {
        return lzEndpoint.getConfig(version, chainId, address(this), configType);
    }
}
