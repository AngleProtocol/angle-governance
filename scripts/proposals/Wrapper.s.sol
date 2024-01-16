// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../Utils.s.sol";

contract Wrapper is Utils {
    function wrapTimelock(
        uint256 chainId,
        SubCall[] memory p
    ) public returns (address target, uint256 value, bytes memory data) {
        TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
            payable(_chainToContract(chainId, ContractType.Timelock))
        );
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        if (batchTargets.length == 1) {
            // In case the operation has already been done add a salt
            uint256 salt = computeSalt(chainId, p);
            // Simple schedule on timelock
            target = address(timelock);
            value = 0;
            data = abi.encodeWithSelector(
                timelock.schedule.selector,
                batchTargets[0],
                batchValues[0],
                batchCalldatas[0],
                bytes32(0),
                salt,
                timelock.getMinDelay()
            );
        } else {
            // In case the operation has already been done add a salt
            uint256 salt = computeSalt(chainId, p);
            target = address(timelock);
            value = 0;
            data = abi.encodeWithSelector(
                timelock.scheduleBatch.selector,
                batchTargets,
                batchValues,
                batchCalldatas,
                bytes32(0),
                salt,
                timelock.getMinDelay()
            );
        }
    }

    function computeSalt(uint256 chainId, SubCall[] memory p) internal returns (uint256 salt) {
        TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
            payable(_chainToContract(chainId, ContractType.Timelock))
        );
        (
            address[] memory batchTargets,
            uint256[] memory batchValues,
            bytes[] memory batchCalldatas
        ) = filterChainSubCalls(chainId, p);
        if (batchTargets.length == 1) {
            salt = 0;
            while (
                timelock.isOperation(
                    timelock.hashOperation(
                        batchTargets[0],
                        batchValues[0],
                        batchCalldatas[0],
                        bytes32(0),
                        bytes32(salt)
                    )
                )
            ) {
                salt++;
            }
        } else {
            salt = 0;
            while (
                timelock.isOperation(
                    timelock.hashOperationBatch(batchTargets, batchValues, batchCalldatas, bytes32(0), bytes32(salt))
                )
            ) {
                salt++;
            }
        }
    }

    function filterChainSubCalls(
        uint256 chainId,
        SubCall[] memory prop
    )
        internal
        pure
        returns (address[] memory batchTargets, uint256[] memory batchValues, bytes[] memory batchCalldatas)
    {
        uint256 count;
        batchTargets = new address[](prop.length);
        batchValues = new uint256[](prop.length);
        batchCalldatas = new bytes[](prop.length);
        for (uint256 j; j < prop.length; j++) {
            if (prop[j].chainId == chainId) {
                batchTargets[count] = prop[j].target;
                batchValues[count] = prop[j].value;
                batchCalldatas[count] = prop[j].data;
                count++;
            }
        }

        assembly ("memory-safe") {
            mstore(batchTargets, count)
            mstore(batchValues, count)
            mstore(batchCalldatas, count)
        }
    }

    function _wrap(
        SubCall[] memory prop
    )
        internal
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, uint256[] memory chainIds)
    {
        targets = new address[](prop.length);
        values = new uint256[](prop.length);
        calldatas = new bytes[](prop.length);
        chainIds = new uint256[](prop.length);

        uint256 finalPropLength;
        uint256 i;
        while (i < prop.length) {
            uint256 chainId = prop[i].chainId;
            // Check the number of same chainId actions
            uint256 count = 1;
            while (i + count < prop.length && prop[i + count].chainId == chainId) {
                count++;
            }

            // Check that the chainId are consecutives
            for (uint256 j = i + count; j < prop.length; j++) {
                if (prop[j].chainId == chainId) {
                    revert("Invalid proposal, chainId must be gathered");
                }
            }

            if (chainId == CHAIN_SOURCE) {
                vm.selectFork(forkIdentifier[CHAIN_SOURCE]);
                (targets[finalPropLength], values[finalPropLength], calldatas[finalPropLength]) = wrapTimelock(
                    chainId,
                    prop
                );
                chainIds[finalPropLength] = chainId;
                finalPropLength += 1;
                i += count;
            } else {
                vm.selectFork(forkIdentifier[chainId]);
                (address target, uint256 value, bytes memory data) = wrapTimelock(chainId, prop);

                address[] memory batchTargets = new address[](1);
                batchTargets[0] = target;
                uint256[] memory batchValues = new uint256[](1);
                batchValues[0] = value;
                bytes[] memory batchCalldatas = new bytes[](1);
                batchCalldatas[0] = data;

                // Wrap for proposal sender
                ProposalSender proposalSender = ProposalSender(
                    _chainToContract(CHAIN_SOURCE, ContractType.ProposalSender)
                );
                targets[finalPropLength] = address(proposalSender);
                values[finalPropLength] = 0.1 ether;
                chainIds[finalPropLength] = chainId;
                calldatas[finalPropLength] = abi.encodeWithSelector(
                    ProposalSender.execute.selector,
                    getLZChainId(chainId),
                    abi.encode(batchTargets, batchValues, new string[](1), batchCalldatas),
                    abi.encodePacked(uint16(1), uint256(300000))
                );
                finalPropLength += 1;
                i += count;
            }
        }
        assembly ("memory-safe") {
            mstore(targets, finalPropLength)
            mstore(values, finalPropLength)
            mstore(calldatas, finalPropLength)
        }
    }
}
