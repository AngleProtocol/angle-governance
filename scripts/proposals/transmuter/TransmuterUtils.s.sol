// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { StdAssertions } from "forge-std/Test.sol";
import "stringutils/strings.sol";

import { CommonUtils } from "utils/src/CommonUtils.sol";
import { ContractType, BASE_18 } from "utils/src/Constants.sol";

contract TransmuterUtils is Script, CommonUtils {
    using strings for *;

    string constant JSON_SELECTOR_PATH = "./scripts/proposals/transmuter/selectors.json";
    string constant JSON_SELECTOR_PATH_REPLACE = "./scripts/proposals/transmuter/selectors_replace.json";
    string constant JSON_SELECTOR_PATH_ADD = "./scripts/proposals/transmuter/selectors_add.json";
    uint256 constant BPS = 1e14;

    address constant EUROC = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
    address constant EUROE = 0x820802Fa8a99901F52e39acD21177b0BE6EE2974;
    address constant EURE = 0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f;
    address constant BC3M = 0x2F123cF3F37CE3328CC9B5b8415f9EC5109b45e7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint128 constant FIREWALL_MINT_EUROC = 0;
    uint128 constant USER_PROTECTION_EUROC = uint128(5 * BPS);
    uint128 constant FIREWALL_MINT_BC3M = uint128(BASE_18);
    uint128 constant USER_PROTECTION_BC3M = uint128(10 * BPS);
    uint96 constant DEVIATION_THRESHOLD_BC3M = uint96(100 * BPS);
    uint32 constant HEARTBEAT = uint32(1 days);

    address constant GETTERS = 0x99fe8557A8F322525262720C52b7d57c56924012;
    address constant REDEEMER = 0xa09735EfbcfF6E76e6EfFF82A9Ad996A85cd0725;
    address constant SETTERS_GOVERNOR = 0x49c7B39A2E01869d39548F232F9B1586DA8Ef9c2;
    address constant SWAPPER = 0xD838bF7fB3b420ac93A7d9f5b40230F78b33536F;

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

    function _arrayBytes32ToBytes4Exclude(
        bytes4[] memory _in,
        bytes4 toExclude
    ) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](_in.length);
        uint256 length = 0;
        for (uint256 i = 0; i < _in.length; ++i) {
            if (_in[i] != toExclude) {
                out[length] = _bytes4ToBytes32(_in[i]);
                length++;
            }
        }
        assembly {
            mstore(out, length)
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
