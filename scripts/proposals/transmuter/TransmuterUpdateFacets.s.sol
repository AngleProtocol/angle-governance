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
import {Getters} from "transmuter/transmuter/facets/Getters.sol";
import {Oracle} from "transmuter/transmuter/facets/Oracle.sol";
// import {Redeemer} from "transmuter/transmuter/facets/Redeemer.sol";
import {SettersGovernor} from "transmuter/transmuter/facets/SettersGovernor.sol";
// import {Swapper} from "transmuter/transmuter/facets/Swapper.sol";
import {ITransmuter, IDiamondCut, ISettersGovernor} from "transmuter/interfaces/ITransmuter.sol";

contract TransmuterUpdateFacets is Wrapper, TransmuterUtils {
    using stdJson for string;

    string[] facetNames;
    string[] replaceFacetNames;
    string[] addFacetNames;
    address[] facetAddressList;

    ITransmuter transmuter;
    IERC20 agEUR;
    address governor;

    SubCall[] private subCalls;

    function _generateFacets() private {
        // First generate the selectors
        facetNames.push("DiamondCut");
        facetNames.push("DiamondLoupe");
        facetNames.push("Getters");
        facetNames.push("Oracle");
        facetNames.push("Redeemer");
        facetNames.push("RewardHandler");
        facetNames.push("SettersGovernor");
        facetNames.push("SettersGuardian");
        facetNames.push("Swapper");
        facetNames.push("DiamondEtherscan");

        string memory json = "";
        for (uint256 i = 0; i < facetNames.length; ++i) {
            bytes4[] memory selectors = _generateSelectors(facetNames[i]);
            vm.serializeBytes32(json, facetNames[i], _arrayBytes4ToBytes32(selectors));
        }
        string memory finalJson = vm.serializeString(json, "useless", "");
        vm.writeJson(finalJson, JSON_SELECTOR_PATH);
    }

    function _updateFacets(uint256 chainId) private {
        uint256 executionChainId = chainId;
        chainId = chainId != 0 ? chainId : CHAIN_SOURCE;

        vm.selectFork(forkIdentifier[executionChainId]);

        transmuter = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgEUR));

        Storage.FacetCut[] memory replaceCut;
        Storage.FacetCut[] memory addCut;

        replaceFacetNames.push("Getters");
        facetAddressList.push(GETTERS);

        replaceFacetNames.push("Redeemer");
        facetAddressList.push(REDEEMER);

        replaceFacetNames.push("SettersGovernor");
        facetAddressList.push(SETTERS_GOVERNOR);

        replaceFacetNames.push("Swapper");
        facetAddressList.push(SWAPPER);

        addFacetNames.push("Oracle");
        facetAddressList.push(ORACLE);

        string memory json = vm.readFile(JSON_SELECTOR_PATH);
        {
            // Build appropriate payload
            uint256 n = replaceFacetNames.length;
            replaceCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors =
                    _arrayBytes32ToBytes4(json.readBytes32Array(string.concat("$.", replaceFacetNames[i])));

                replaceCut[i] = Storage.FacetCut({
                    facetAddress: facetAddressList[i],
                    action: Storage.FacetCutAction.Replace,
                    functionSelectors: selectors
                });
            }
        }

        {
            // Build appropriate payload
            uint256 r = replaceFacetNames.length;
            uint256 n = addFacetNames.length;
            addCut = new Storage.FacetCut[](n);
            for (uint256 i = 0; i < n; ++i) {
                // Get Selectors from json
                bytes4[] memory selectors =
                    _arrayBytes32ToBytes4(json.readBytes32Array(string.concat("$.", addFacetNames[i])));
                addCut[i] = Storage.FacetCut({
                    facetAddress: facetAddressList[r + i],
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

        _generateFacets();
        for (uint256 i = 0; i < chainIds.length; i++) {
            _updateFacets(chainIds[i]);
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, uint256[] memory chainIds2) =
            _wrap(subCalls);
        _serializeJson(targets, values, calldatas, chainIds2, description);
    }
}
