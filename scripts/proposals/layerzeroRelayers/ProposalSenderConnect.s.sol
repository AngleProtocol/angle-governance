// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";

contract ProposalSenderConnect is Wrapper {
    function _setReceiver(uint256 chainId, address sender) private returns (address, uint256, bytes memory) {
        address receiver = _chainToContract(chainId, ContractType.ProposalReceiver);
        return (
            sender,
            0,
            abi.encodeWithSelector(
                ProposalSender.setTrustedRemoteAddress.selector,
                getLZChainId(chainId),
                abi.encodePacked(receiver)
            )
        );
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://QmRSdyuXeemVEn97RPRSiit6UEUonvwVr9we7bEe2w8v2E";

        address sender = _chainToContract(CHAIN_SOURCE, ContractType.ProposalSender);

        address[] memory targets = new address[](chainIds.length);
        uint256[] memory values = new uint256[](chainIds.length);
        bytes[] memory calldatas = new bytes[](chainIds.length);

        vm.selectFork(forkIdentifier[CHAIN_SOURCE]);
        for (uint256 i = 0; i < chainIds.length; i++) {
            (address target, uint256 value, bytes memory data) = _setReceiver(chainIds[i], sender);
            targets[i] = target;
            values[i] = value;
            calldatas[i] = data;
        }

        _serializeJson(targets, values, calldatas, chainIds, description);
    }
}
