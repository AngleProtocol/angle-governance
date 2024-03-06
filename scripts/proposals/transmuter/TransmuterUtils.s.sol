// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {StdAssertions} from "forge-std/Test.sol";
import "stringutils/strings.sol";

import {CommonUtils} from "utils/src/CommonUtils.sol";
import {ContractType, BASE_18} from "utils/src/Constants.sol";

contract TransmuterUtils is Script, CommonUtils {
    using strings for *;

    string constant JSON_SELECTOR_PATH = "./scripts/proposals/transmuter/selectors.json";
    uint256 constant BPS = 1e14;

    address constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
    address constant EUROE = 0x820802Fa8a99901F52e39acD21177b0BE6EE2974;
    address constant EURE = 0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f;
    address constant BC3M = 0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint128 constant FIREWALL_MINT_EUROC = 0;
    uint128 constant FIREWALL_BURN_EUROC = uint128(5 * BPS);
    uint128 constant FIREWALL_MINT_BC3M = uint128(BASE_18);
    uint128 constant FIREWALL_BURN_BC3M = uint128(100 * BPS);
    uint96 constant DEVIATION_THRESHOLD_BC3M = uint96(100 * BPS);
    uint32 constant HEARTBEAT = uint32(1 days);

    address constant GETTERS = 0x37eB0572eb61db3B819570Cf65114ff6dB6C06A2;
    address constant REDEEMER = 0x028e1f0DB25DAF4ce8C895215deAfbCE7A873b24;
    address constant SETTERS_GOVERNOR = 0xc3ef7ed4F97450Ae8dA2473068375788BdeB5c5c;
    address constant SWAPPER = 0x954eC713a3915B504a6F288563e5218F597e1895;
    address constant ORACLE = 0x44E3d3BBa34E16a67c633dAF86114284FC628819;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _bytes4ToBytes32(bytes4 _in) internal pure returns (bytes32 out) {
        assembly {
            out := _in
        }
    }

    function _arrayBytes4ToBytes32(bytes4[] memory _in) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](_in.length);
        for (uint256 i = 0; i < _in.length; ++i) {
            out[i] = _bytes4ToBytes32(_in[i]);
        }
    }

    function _arrayBytes32ToBytes4(bytes32[] memory _in) internal pure returns (bytes4[] memory out) {
        out = new bytes4[](_in.length);
        for (uint256 i = 0; i < _in.length; ++i) {
            out[i] = bytes4(_in[i]);
        }
    }

    function consoleLogBytes4Array(bytes4[] memory _in) internal view {
        for (uint256 i = 0; i < _in.length; ++i) {
            console.logBytes4(_in[i]);
        }
    }
}
