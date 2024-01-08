// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import "transmuter/transmuter/Storage.sol" as Storage;
import { ISettersGuardian } from "transmuter/interfaces/ISetters.sol";
import { IDiamondCut } from "transmuter/interfaces/IDiamondCut.sol";

import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";
import { Treasury } from "borrow/treasury/Treasury.sol";
import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

contract InitAndBootstrap is Utils {
    function run() external {
        bytes memory transactions;
        uint8 isDelegateCall = 0;
        uint256 value = 0;
        address to;

        uint256 chainId = vm.envUint("CHAIN_ID");

        ITransmuter transmuter = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgEUR));
        // Update Redeemer to non via ir implementation
        {
            Storage.FacetCut[] memory addCut = new Storage.FacetCut[](1);
            Storage.FacetCut[] memory removeCut = new Storage.FacetCut[](1);
            // Get Selectors from json
            bytes4[] memory selectors = new bytes4[](4);
            selectors[0] = hex"d703a0cd";
            selectors[1] = hex"815822c1";
            selectors[2] = hex"2e7639bc";
            selectors[3] = hex"fd7daaf8";
            addCut[0] = Storage.FacetCut({
                // new Redeemer address
                facetAddress: 0x1e45b65CdD3712fEf0024d063d6574A609985E59,
                action: Storage.FacetCutAction.Add,
                functionSelectors: selectors
            });

            removeCut[0] = Storage.FacetCut({
                facetAddress: address(0),
                action: Storage.FacetCutAction.Remove,
                functionSelectors: selectors
            });

            to = address(transmuter);
            bytes memory callData;
            {
                bytes memory data = abi.encodeWithSelector(
                    IDiamondCut.diamondCut.selector,
                    removeCut,
                    address(0),
                    callData
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }

            {
                bytes memory data = abi.encodeWithSelector(
                    IDiamondCut.diamondCut.selector,
                    addCut,
                    address(0),
                    callData
                );
                uint256 dataLength = data.length;
                bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
                transactions = abi.encodePacked(transactions, internalTx);
            }
        }

        // Transfer funds to make live transmuter
        {
            to = EUROC;
            bytes memory data = abi.encodeWithSelector(
                IERC20.transfer.selector,
                address(transmuter),
                9_500_000 * 10 ** IERC20Metadata(to).decimals()
            );
            uint256 dataLength = data.length;
            bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
            transactions = abi.encodePacked(transactions, internalTx);
        }

        {
            to = BC3M;
            bytes memory data = abi.encodeWithSelector(
                IERC20.transfer.selector,
                address(transmuter),
                38446 * 10 ** IERC20Metadata(to).decimals()
            );
            uint256 dataLength = data.length;
            bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
            transactions = abi.encodePacked(transactions, internalTx);
        }

        // add transmuter as `agEUR` minter
        {
            address treasury = address(_chainToContract(chainId, ContractType.TreasuryAgEUR));
            to = address(treasury);
            bytes memory data = abi.encodeWithSelector(Treasury.addMinter.selector, address(transmuter));
            uint256 dataLength = data.length;
            bytes memory internalTx = abi.encodePacked(isDelegateCall, to, value, dataLength, data);
            transactions = abi.encodePacked(transactions, internalTx);
        }

        // bytes memory payloadMultiSend = abi.encodeWithSelector(MultiSend.multiSend.selector, transactions);
        // address multiSend = address(_chainToMultiSend(chainId));
        // _serializeJson(chainId, multiSend, 0, payloadMultiSend, Enum.Operation.DelegateCall, hex"");
    }
}
