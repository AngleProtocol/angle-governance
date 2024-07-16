// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "oz-v5/utils/ReentrancyGuard.sol";
import "lz/lzApp/NonblockingLzApp.sol";
import "./utils/Errors.sol";

/// @title ProposalReceiver
/// @author LayerZero Labs
/// @notice Executes proposal transactions sent from the main chain
/// @dev The owner of this contract controls LayerZero configuration. When used in production the owner
/// should be set to a Timelock or this contract itself.
/// @dev This implementation is non-blocking meaning the failed messages will not block the future messages
/// from the source.
/// @dev Full fork from:
/// https://github.com/LayerZero-Labs/omnichain-governance-executor/blob/main/contracts/OmnichainGovernanceExecutor.sol
contract ProposalReceiver is NonblockingLzApp, ReentrancyGuard {
    using BytesLib for bytes;
    using ExcessivelySafeCall for address;

    event ProposalExecuted(bytes payload);
    event ProposalFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _reason);

    constructor(address _endpoint) NonblockingLzApp(_endpoint) Ownable(msg.sender) {}

    // overriding the virtual function in LzReceiver
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        bytes32 hashedPayload = keccak256(_payload);
        uint256 gasToStoreAndEmit = 30000; // enough gas to ensure we can store the payload and emit the event

        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft() - gasToStoreAndEmit,
            150,
            abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload)
        );
        // try-catch all errors/exceptions
        if (!success) {
            failedMessages[_srcChainId][_srcAddress][_nonce] = hashedPayload;
            // Retrieve payload from the src side tx if needed to clear
            emit ProposalFailed(_srcChainId, _srcAddress, _nonce, reason);
        }
    }

    /// @notice Executes the proposal
    /// @dev Called by LayerZero Endpoint when a message from the source is received
    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal virtual override {
        (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) = abi
            .decode(_payload, (address[], uint256[], string[], bytes[]));

        for (uint256 i = 0; i < targets.length; i++) {
            _executeTransaction(targets[i], values[i], signatures[i], calldatas[i]);
        }
        emit ProposalExecuted(_payload);
    }

    function _executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) private nonReentrant {
        bytes memory callData = bytes(signature).length == 0
            ? data
            : abi.encodePacked(bytes4(keccak256(bytes(signature))), data);

        // solium-disable-next-line security/no-call-value
        (bool success, ) = target.call{ value: value }(callData);
        if (!success) revert OmnichainGovernanceExecutorTxExecReverted();
    }

    receive() external payable {}
}
