// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {ScriptHelpers} from "../ScriptHelpers.t.sol";
import {TransmuterUtils} from "../../../scripts/proposals/transmuter/TransmuterUtils.s.sol";
import "../../../scripts/Constants.s.sol";
import {OldTransmuter} from "../../../scripts/interfaces/ITransmuter.sol";
import "transmuter/transmuter/Storage.sol" as Storage;

contract TransmuterUpdateFacetsTest is ScriptHelpers, TransmuterUtils {
    using stdJson for string;

    ITransmuter transmuter;
    bytes public oracleConfigEUROC;
    bytes public oracleConfigBC3M;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();

        // Now test that everything is as expected
        for (uint256 i; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            transmuter = ITransmuter(payable(_chainToContract(chainId, ContractType.TransmuterAgEUR)));
            vm.selectFork(forkIdentifier[chainId]);
            _testAccessControlManager();
            _testAgToken();
            _testGetCollateralList();
        }
    }

    function _testAccessControlManager() internal {
        assertEq(address(transmuter.accessControlManager()), _chainToContract(CHAIN_SOURCE, ContractType.CoreBorrow));
    }

    function _testAgToken() internal {
        assertEq(address(transmuter.agToken()), _chainToContract(CHAIN_SOURCE, ContractType.AgEUR));
    }

    function _testGetCollateralList() internal {
        address[] memory collateralList = transmuter.getCollateralList();
        assertEq(collateralList.length, 2);
        assertEq(collateralList[0], address(EUROC));
        assertEq(collateralList[1], address(BC3M));
    }

    function testUnit_Upgrade_GetCollateralInfo() external {
        {
            Storage.Collateral memory collatInfoEUROC = transmuter.getCollateralInfo(address(EUROC));
            assertEq(collatInfoEUROC.isManaged, 0);
            assertEq(collatInfoEUROC.isMintLive, 1);
            assertEq(collatInfoEUROC.isBurnLive, 1);
            assertEq(collatInfoEUROC.decimals, 6);
            assertEq(collatInfoEUROC.onlyWhitelisted, 0);
            assertApproxEqRel(collatInfoEUROC.normalizedStables, 10893124 * BASE_18, 100 * BPS);
            assertEq(collatInfoEUROC.oracleConfig, oracleConfigEUROC);
            assertEq(collatInfoEUROC.whitelistData.length, 0);
            assertEq(collatInfoEUROC.managerData.subCollaterals.length, 0);
            assertEq(collatInfoEUROC.managerData.config.length, 0);

            {
                assertEq(collatInfoEUROC.xFeeMint.length, 5);
                assertEq(collatInfoEUROC.yFeeMint.length, 5);
                assertEq(collatInfoEUROC.xFeeMint[0], 0);
                assertEq(collatInfoEUROC.yFeeMint[0], 0);
                assertEq(collatInfoEUROC.xFeeMint[1], 730000000);
                assertEq(collatInfoEUROC.yFeeMint[1], 0);
                assertEq(collatInfoEUROC.xFeeMint[2], 740000000);
                assertEq(collatInfoEUROC.yFeeMint[2], 500000);
                assertEq(collatInfoEUROC.xFeeMint[3], 745000000);
                assertEq(collatInfoEUROC.yFeeMint[3], 1000000);
                assertEq(collatInfoEUROC.xFeeMint[4], 750000000);
                assertEq(collatInfoEUROC.yFeeMint[4], 1000000000000);
            }
            {
                assertEq(collatInfoEUROC.xFeeBurn.length, 5);
                assertEq(collatInfoEUROC.yFeeBurn.length, 5);
                assertEq(collatInfoEUROC.xFeeBurn[0], 1000000000);
                assertEq(collatInfoEUROC.yFeeBurn[0], 0);
                assertEq(collatInfoEUROC.xFeeBurn[1], 670000000);
                assertEq(collatInfoEUROC.yFeeBurn[1], 0);
                assertEq(collatInfoEUROC.xFeeBurn[2], 590000000);
                assertEq(collatInfoEUROC.yFeeBurn[2], 1000000);
                assertEq(collatInfoEUROC.xFeeBurn[3], 505000000);
                assertEq(collatInfoEUROC.yFeeBurn[3], 1000000);
                assertEq(collatInfoEUROC.xFeeBurn[4], 500000000);
                assertEq(collatInfoEUROC.yFeeBurn[4], 999000000);
            }
        }

        {
            Storage.Collateral memory collatInfoBC3M = transmuter.getCollateralInfo(address(BC3M));
            assertEq(collatInfoBC3M.isManaged, 0);
            assertEq(collatInfoBC3M.isMintLive, 1);
            assertEq(collatInfoBC3M.isBurnLive, 1);
            assertEq(collatInfoBC3M.decimals, 18);
            assertEq(collatInfoBC3M.onlyWhitelisted, 1);
            assertApproxEqRel(collatInfoBC3M.normalizedStables, 6236650 * BASE_18, 100 * BPS);
            assertEq(collatInfoBC3M.oracleConfig, oracleConfigBC3M);
            {
                (Storage.WhitelistType whitelist, bytes memory data) =
                    abi.decode(collatInfoBC3M.whitelistData, (Storage.WhitelistType, bytes));
                address keyringGuard = abi.decode(data, (address));
                assertEq(uint8(whitelist), uint8(Storage.WhitelistType.BACKED));
                assertEq(keyringGuard, 0x9391B14dB2d43687Ea1f6E546390ED4b20766c46);
            }
            assertEq(collatInfoBC3M.managerData.subCollaterals.length, 0);
            assertEq(collatInfoBC3M.managerData.config.length, 0);

            {
                assertEq(collatInfoBC3M.xFeeMint.length, 4);
                assertEq(collatInfoBC3M.yFeeMint.length, 4);
                assertEq(collatInfoBC3M.xFeeMint[0], 0);
                assertEq(collatInfoBC3M.yFeeMint[0], 0);
                assertEq(collatInfoBC3M.xFeeMint[1], 400000000);
                assertEq(collatInfoBC3M.yFeeMint[1], 0);
                assertEq(collatInfoBC3M.xFeeMint[2], 495000000);
                assertEq(collatInfoBC3M.yFeeMint[2], 2000000);
                assertEq(collatInfoBC3M.xFeeMint[3], 500000000);
                assertEq(collatInfoBC3M.yFeeMint[3], 1000000000000);
            }
            {
                assertEq(collatInfoBC3M.xFeeBurn.length, 3);
                assertEq(collatInfoBC3M.yFeeBurn.length, 3);
                assertEq(collatInfoBC3M.xFeeBurn[0], 1000000000);
                assertEq(collatInfoBC3M.yFeeBurn[0], 5000000);
                assertEq(collatInfoBC3M.xFeeBurn[1], 260000000);
                assertEq(collatInfoBC3M.yFeeBurn[1], 5000000);
                assertEq(collatInfoBC3M.xFeeBurn[2], 250000000);
                assertEq(collatInfoBC3M.yFeeBurn[2], 999000000);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ORACLE                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testUnit_Upgrade_getOracleValues_Success() external {
        _checkOracleValues(address(EUROC), BASE_18, FIREWALL_MINT_EUROC, FIREWALL_BURN_EUROC);
        _checkOracleValues(address(BC3M), (11944 * BASE_18) / 100, FIREWALL_MINT_BC3M, FIREWALL_BURN_BC3M);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CHECKS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _checkOracleValues(address collateral, uint256 targetValue, uint128 firewallMint, uint128 firewallBurn)
        internal
    {
        (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) =
            transmuter.getOracleValues(collateral);
        assertApproxEqRel(targetValue, redemption, 200 * BPS);
        assertEq(burn, redemption);
        if (redemption * BASE_18 < targetValue * (BASE_18 - firewallBurn)) {
            assertEq(mint, redemption);
            assertEq(ratio, (redemption * BASE_18) / targetValue);
        } else if (redemption < targetValue) {
            assertEq(mint, redemption);
            assertEq(ratio, BASE_18);
        } else if (redemption * BASE_18 < targetValue * ((BASE_18 + firewallMint))) {
            assertEq(mint, redemption);
            assertEq(ratio, BASE_18);
        } else {
            assertEq(mint, targetValue);
            assertEq(ratio, BASE_18);
        }
    }
}
