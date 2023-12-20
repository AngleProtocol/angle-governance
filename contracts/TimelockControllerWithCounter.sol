// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { TimelockController } from "oz/governance/TimelockController.sol";

/// @title AngleGovernor
/// @author Angle Labs, Inc
/// @dev Timelock controller of Angle governance system, extending OpenZeppelin one
/// @dev This contract overrides some OpenZeppelin functions, to have a mapping between
///      the index (chronological) of the proposal and its id
/// @custom:security-contact contact@angle.money
contract TimelockControllerWithCounter is TimelockController {
    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Counter on the number of proposals created
    uint256 public counterProposals;
    /// @notice Mapping between index and proposal ID
    mapping(uint256 => bytes32) public proposalIds;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  EXTERNAL OVERRIDES                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc TimelockController
    /// @dev No role check as it is done in the parent contract
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public override {
        super.schedule(target, value, data, predecessor, salt, delay);
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        proposalIds[counterProposals++] = id;
    }

    /// @inheritdoc TimelockController
    /// @dev No role check as it is done in the parent contract
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public override {
        super.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        proposalIds[counterProposals++] = id;
    }
}
