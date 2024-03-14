// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Wrapper} from "../Wrapper.s.sol";
import {TransmuterUtils} from "./TransmuterUtils.s.sol";
import "../../Constants.s.sol";
import {OldTransmuter} from "../../interfaces/ITransmuter.sol";

import {IERC20} from "oz-v5/token/ERC20/IERC20.sol";
import "transmuter/transmuter/Storage.sol" as Storage;
import {DiamondCut} from "transmuter/transmuter/facets/DiamondCut.sol";
import {DiamondEtherscan} from "transmuter/transmuter/facets/DiamondEtherscan.sol";
import {DiamondLoupe} from "transmuter/transmuter/facets/DiamondLoupe.sol";
import {DiamondProxy} from "transmuter/transmuter/DiamondProxy.sol";
import {Getters} from "transmuter/transmuter/facets/Getters.sol";
import {Redeemer} from "transmuter/transmuter/facets/Redeemer.sol";
import {RewardHandler} from "transmuter/transmuter/facets/RewardHandler.sol";
import {SettersGovernor} from "transmuter/transmuter/facets/SettersGovernor.sol";
import {SettersGuardian} from "transmuter/transmuter/facets/SettersGuardian.sol";
import {Swapper} from "transmuter/transmuter/facets/Swapper.sol";
import {ITransmuter, IDiamondCut, ISettersGovernor} from "transmuter/interfaces/ITransmuter.sol";

contract TransmuterUpdateFacets is Wrapper, TransmuterUtils {
    using stdJson for string;

    string[] replaceFacetNames;
    string[] addFacetNames;
    address[] replaceFacetAddressList;
    address[] addFacetAddressList;

    ITransmuter transmuter;
    IERC20 agEUR;
    address governor;

    SubCall[] private subCalls;

    function _updateFacets(uint256 chainId) private {
        uint256 executionChainId = chainId;
        chainId = chainId != 0 ? chainId : CHAIN_SOURCE;

        vm.selectFork(forkIdentifier[executionChainId]);

        transmuter = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgEUR));

        Storage.FacetCut[] memory replaceCut;
        Storage.FacetCut[] memory addCut;

        replaceFacetNames.push("Getters");
        replaceFacetAddressList.push(GETTERS);

        replaceFacetNames.push("Redeemer");
        replaceFacetAddressList.push(REDEEMER);

        replaceFacetNames.push("SettersGovernor");
        replaceFacetAddressList.push(SETTERS_GOVERNOR);

        replaceFacetNames.push("Swapper");
        replaceFacetAddressList.push(SWAPPER);

        addFacetNames.push("SettersGovernor");
        addFacetAddressList.push(SETTERS_GOVERNOR);

        {
            string memory jsonReplace = vm.readFile(JSON_SELECTOR_PATH_REPLACE);
            // Build appropriate payload
            uint256 n = replaceFacetNames.length;
            replaceCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors = _arrayBytes32ToBytes4(
                    jsonReplace.readBytes32Array(string.concat("$.", replaceFacetNames[i]))
                );

                replaceCut[i] = Storage.FacetCut({
                    facetAddress: replaceFacetAddressList[i],
                    action: Storage.FacetCutAction.Replace,
                    functionSelectors: selectors
                });
            }
        }

        {
            string memory jsonAdd = vm.readFile(JSON_SELECTOR_PATH_ADD);
            // Build appropriate payload
            uint256 n = addFacetNames.length;
            addCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors = _arrayBytes32ToBytes4(
                    jsonAdd.readBytes32Array(string.concat("$.", addFacetNames[i]))
                );
                addCut[i] = Storage.FacetCut({
                    facetAddress: addFacetAddressList[i],
                    action: Storage.FacetCutAction.Add,
                    functionSelectors: selectors
                });   
            }
        }

        // Get the previous oracles configs
        (
            Storage.OracleReadType oracleTypeEUROC,
            Storage.OracleReadType targetTypeEUROC,
            bytes memory oracleDataEUROC,
            bytes memory targetDataEUROC
        ) = OldTransmuter(address(transmuter)).getOracle(address(EUROC));

        (Storage.OracleReadType oracleTypeBC3M,, bytes memory oracleDataBC3M,) =
            OldTransmuter(address(transmuter)).getOracle(address(BC3M));

        (,,,, uint256 currentBC3MPrice) = transmuter.getOracleValues(address(BC3M));

        bytes memory callData;
        // set the right implementations
        subCalls.push(
            SubCall(
                chainId,
                address(transmuter),
                0,
                abi.encodeWithSelector(IDiamondCut.diamondCut.selector, replaceCut, address(0), callData)
            )
        );
        subCalls.push(
            SubCall(
                chainId,
                address(transmuter),
                0,
                abi.encodeWithSelector(IDiamondCut.diamondCut.selector, addCut, address(0), callData)
            )
        );

        // update the oracles
        subCalls.push(
            SubCall(
                chainId,
                address(transmuter),
                0,
                abi.encodeWithSelector(
                    ISettersGovernor.setOracle.selector,
                    EUROC,
                    abi.encode(
                        oracleTypeEUROC,
                        targetTypeEUROC,
                        oracleDataEUROC,
                        targetDataEUROC,
                        abi.encode(FIREWALL_MINT_EUROC, FIREWALL_BURN_EUROC)
                    )
                )
            )
        );

        subCalls.push(
            SubCall(
                chainId,
                address(transmuter),
                0,
                abi.encodeWithSelector(
                    ISettersGovernor.setOracle.selector,
                    BC3M,
                    abi.encode(
                        oracleTypeBC3M,
                        Storage.OracleReadType.MAX,
                        oracleDataBC3M,
                        // We can hope that the oracleDataBC3M won't move much before the proposal is executed
                        abi.encode(currentBC3MPrice, DEVIATION_THRESHOLD_BC3M, uint96(block.timestamp), HEARTBEAT),
                        abi.encode(FIREWALL_MINT_BC3M, FIREWALL_BURN_BC3M)
                    )
                )
            )
        );
    }

    function run() external {
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory description = "ipfs://";

        for (uint256 i = 0; i < chainIds.length; i++) {
            _updateFacets(chainIds[i]);
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, uint256[] memory chainIds2) =
            _wrap(subCalls);
        _serializeJson(targets, values, calldatas, chainIds2, description);
    }
}
