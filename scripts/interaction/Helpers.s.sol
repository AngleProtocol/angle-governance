// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

// import { console } from "forge-std/console.sol";
// import { stdJson } from "forge-std/StdJson.sol";
// import "stringutils/strings.sol";
// import "../Utils.s.sol";
// import { SubCall } from "../../test/unit/Proposal.sol";
// import "oz/interfaces/IERC20.sol";

// import { IveANGLEVotingDelegation } from "contracts/interfaces/IveANGLEVotingDelegation.sol";
// import { ERC20 } from "oz/token/ERC20/ERC20.sol";
// import "contracts/interfaces/IveANGLE.sol";

// import { AngleGovernor } from "contracts/AngleGovernor.sol";
// import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
// import { ProposalSender } from "contracts/ProposalSender.sol";
// import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
// import { VeANGLEVotingDelegation, ECDSA } from "contracts/VeANGLEVotingDelegation.sol";

// /// @dev To deploy on a different chain, just replace the import of the `Constants.s.sol` file by a file which has the
// /// constants defined for the chain of your choice.
// contract Helpers is Utils {
//     using stdJson for string;
//     using strings for *;

//     /// @notice Build the governor proposal based on all the transaction that need to be executed
//     function _wrap(
//         SubCall[] memory prop
//     ) internal returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) {
//         targets = new address[](prop.length);
//         values = new uint256[](prop.length);
//         calldatas = new bytes[](prop.length);
//         uint256 finalPropLength;
//         uint256 i;
//         while (i < prop.length) {
//             uint256 chainId = prop[i].chainId;
//             // Check the number of same chainId actions
//             uint256 count = 1;
//             while (i + count < prop.length && prop[i + count].chainId == chainId) {
//                 count++;
//             }

//             // Check that the chainId are consecutives
//             for (uint256 j = i + count; j < prop.length; j++) {
//                 if (prop[j].chainId == chainId) {
//                     revert("Invalid proposal, chainId must be gathered");
//                 }
//             }

//             if (chainId == 1) {
//                 vm.selectFork(forkIdentifier[1]);

//                 (
//                     address[] memory batchTargets,
//                     uint256[] memory batchValues,
//                     bytes[] memory batchCalldatas
//                 ) = filterChainSubCalls(chainId, prop);
//                 (targets[finalPropLength], values[finalPropLength], calldatas[finalPropLength]) = wrapTimelock(
//                     chainId,
//                     prop
//                 );
//                 finalPropLength += 1;
//                 i += count;
//             } else {
//                 vm.selectFork(forkIdentifier[chainId]);

//                 (
//                     address[] memory batchTargets,
//                     uint256[] memory batchValues,
//                     bytes[] memory batchCalldatas
//                 ) = filterChainSubCalls(chainId, prop);
//                 (address target, uint256 value, bytes memory data) = wrapTimelock(chainId, prop);

//                 batchTargets = new address[](1);
//                 batchTargets[0] = target;
//                 batchValues = new uint256[](1);
//                 batchValues[0] = value;
//                 batchCalldatas = new bytes[](1);
//                 batchCalldatas[0] = data;

//                 // Wrap for proposal sender
//                 targets[finalPropLength] = address(proposalSender());
//                 values[finalPropLength] = 0.1 ether;
//                 calldatas[finalPropLength] = abi.encodeWithSelector(
//                     proposalSender().execute.selector,
//                     getLZChainId(chainId),
//                     abi.encode(batchTargets, batchValues, new string[](1), batchCalldatas),
//                     abi.encodePacked(uint16(1), uint256(300000))
//                 );
//                 finalPropLength += 1;
//                 i += count;
//             }
//         }
//         assembly ("memory-safe") {
//             mstore(targets, finalPropLength)
//             mstore(values, finalPropLength)
//             mstore(calldatas, finalPropLength)
//         }
//         vm.selectFork(forkIdentifier[1]); // Set back the fork to mainnet
//     }

//     function filterChainSubCalls(
//         uint256 chainId,
//         SubCall[] memory prop
//     )
//         internal
//         pure
//         returns (address[] memory batchTargets, uint256[] memory batchValues, bytes[] memory batchCalldatas)
//     {
//         uint256 count;
//         batchTargets = new address[](prop.length);
//         batchValues = new uint256[](prop.length);
//         batchCalldatas = new bytes[](prop.length);
//         for (uint256 j; j < prop.length; j++) {
//             if (prop[j].chainId == chainId) {
//                 batchTargets[count] = prop[j].target;
//                 batchValues[count] = prop[j].value;
//                 batchCalldatas[count] = prop[j].data;
//                 count++;
//             }
//         }

//         assembly ("memory-safe") {
//             mstore(batchTargets, count)
//             mstore(batchValues, count)
//             mstore(batchCalldatas, count)
//         }
//     }

//     function wrapTimelock(
//         uint256 chainId,
//         SubCall[] memory p
//     ) public view returns (address target, uint256 value, bytes memory data) {
//         (
//             address[] memory batchTargets,
//             uint256[] memory batchValues,
//             bytes[] memory batchCalldatas
//         ) = filterChainSubCalls(chainId, p);
//         if (batchTargets.length == 1) {
//             // In case the operation has already been done add a salt
//             uint256 salt = computeSalt(chainId, p);
//             // Simple schedule on timelock
//             target = address(timelock(chainId));
//             value = 0;
//             data = abi.encodeWithSelector(
//                 timelock(chainId).schedule.selector,
//                 batchTargets[0],
//                 batchValues[0],
//                 batchCalldatas[0],
//                 bytes32(0),
//                 salt,
//                 timelock(chainId).getMinDelay()
//             );
//         } else {
//             // In case the operation has already been done add a salt
//             uint256 salt = computeSalt(chainId, p);
//             target = address(timelock(chainId));
//             value = 0;
//             data = abi.encodeWithSelector(
//                 timelock(chainId).scheduleBatch.selector,
//                 batchTargets,
//                 batchValues,
//                 batchCalldatas,
//                 bytes32(0),
//                 salt,
//                 timelock(chainId).getMinDelay()
//             );
//         }
//     }

//     function computeSalt(uint256 chainId, SubCall[] memory p) internal view returns (uint256 salt) {
//         (
//             address[] memory batchTargets,
//             uint256[] memory batchValues,
//             bytes[] memory batchCalldatas
//         ) = filterChainSubCalls(chainId, p);
//         if (batchTargets.length == 1) {
//             salt = 0;
//             while (
//                 timelock(chainId).isOperation(
//                     timelock(chainId).hashOperation(
//                         batchTargets[0],
//                         batchValues[0],
//                         batchCalldatas[0],
//                         bytes32(0),
//                         bytes32(salt)
//                     )
//                 )
//             ) {
//                 salt++;
//             }
//         } else {
//             salt = 0;
//             while (
//                 timelock(chainId).isOperation(
//                     timelock(chainId).hashOperationBatch(
//                         batchTargets,
//                         batchValues,
//                         batchCalldatas,
//                         bytes32(0),
//                         bytes32(salt)
//                     )
//                 )
//             ) {
//                 salt++;
//             }
//         }
//     }
// }
