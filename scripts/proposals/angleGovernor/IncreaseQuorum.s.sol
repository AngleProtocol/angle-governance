// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Wrapper} from "../Wrapper.s.sol";
import {GovernorVotesQuorumFraction} from "oz-v5/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorShortCircuit} from "contracts/external/GovernorShortCircuit.sol";
import "../../Constants.s.sol";

contract IncreaseQuorum is Wrapper {
    SubCall[] private subCalls;

    function _setQuorum(uint256 chainId, uint256 quorum) private {
        vm.selectFork(forkIdentifier[chainId]);
        address angleGovernor = _chainToContract(chainId, ContractType.Governor);

        subCalls.push(
            SubCall(
                chainId,
                angleGovernor,
                0,
                abi.encodeWithSelector(GovernorVotesQuorumFraction.updateQuorumNumerator.selector, quorum)
            )
        );
    }

    function _setQuorumShortCircuit(uint256 chainId, uint256 quorum) private {
        vm.selectFork(forkIdentifier[chainId]);
        address angleGovernor = _chainToContract(chainId, ContractType.Governor);

        subCalls.push(
            SubCall(
                chainId,
                angleGovernor,
                0,
                abi.encodeWithSelector(GovernorShortCircuit.updateShortCircuitNumerator.selector, quorum)
            )
        );
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmXpXXaUYCtUb4w9T2kEtu8t1JwpSv7tqTFwMETKgimcsf";

        /**
         * TODO  complete
         */
        uint256 quorum = 20;
        uint256 quorumShortCircuit = 75;
        /**
         * END  complete
         */
        for (uint256 i = 0; i < chainIds.length; i++) {
            _setQuorum(chainIds[i], quorum);
            _setQuorumShortCircuit(chainIds[i], quorumShortCircuit);
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, uint256[] memory chainIds2) =
            _wrap(subCalls);
        _serializeJson(targets, values, calldatas, chainIds2, description);
    }
}
