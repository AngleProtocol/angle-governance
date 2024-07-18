// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Wrapper } from "../Wrapper.s.sol";
import "../../Constants.s.sol";
import { ProxyAdmin } from "oz/proxy/transparent/ProxyAdmin.sol";

contract SetupLinea is Wrapper {
    SubCall[] private subCalls;
    // Linea
    uint256 public constant chainId = CHAIN_LINEA;

    function _setMaxRateSavings(
        address savings,
        address treasury,
        uint256 maxRate,
        string memory name,
        string memory symbol,
        address keeper
    ) private {
        bytes memory upgradeData = abi.encodeWithSelector(
            IProxyAdmin.upgrade.selector,
            savings,
            // SavingsNameable implem on Linea
            0x2C28Bd22aB59341892e85aD76d159d127c4B03FA
        );
        bytes memory nameAndSymbolData = abi.encodeWithSelector(INameable.setNameAndSymbol.selector, name, symbol);
        bytes memory maxRateData = abi.encodeWithSelector(ISavings.setMaxRate.selector, maxRate);
        bytes memory keeperData = abi.encodeWithSelector(ISavings.toggleTrusted.selector, keeper);
        bytes memory minterData = abi.encodeWithSelector(ITreasuryGovernance.addMinter.selector, savings);
        subCalls.push(SubCall(chainId, 0x1D941EF0D3Bba4ad67DBfBCeE5262F4CEE53A32b, 0, upgradeData));
        subCalls.push(SubCall(chainId, treasury, 0, minterData));
        subCalls.push(SubCall(chainId, savings, 0, nameAndSymbolData));
        subCalls.push(SubCall(chainId, savings, 0, maxRateData));
        subCalls.push(SubCall(chainId, savings, 0, keeperData));
    }

    function run() external {
        address stUSD = 0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776;
        address stEUR = 0x004626A008B1aCdC4c74ab51644093b155e59A23;
        address treasuryEUR = 0xf1dDcACA7D17f8030Ab2eb54f2D9811365EFe123;
        address treasuryUSD = 0x840b25c87B626a259CA5AC32124fA752F0230a72;
        address keeper = 0xa9bbbDDe822789F123667044443dc7001fb43C01;
        uint256 maxRateUSD = 10669464645118865408;
        uint256 maxRateEUR = 3022265993024575488;
        string memory nameUSD = "Staked USDA";
        string memory symbolUSD = "stUSD";
        string memory nameEUR = "Staked EURA";
        string memory symbolEUR = "stEUR";

        {
            bytes memory treasuryData = abi.encodeWithSelector(
                ITreasuryGovernance.setCore.selector,
                // AccessControlManager Core
                0x4b1E2c2762667331Bc91648052F646d1b0d35984
            );
            subCalls.push(SubCall(chainId, treasuryUSD, 0, treasuryData));
        }

        _setMaxRateSavings(stUSD, treasuryUSD, maxRateUSD, nameUSD, symbolUSD, keeper);
        _setMaxRateSavings(stEUR, treasuryEUR, maxRateEUR, nameEUR, symbolEUR, keeper);

        string memory description = "ipfs://QmRSdyuXeemVEn97RPRSiit6UEUonvwVr9we7bEe2w8v2E";

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            uint256[] memory chainIds2
        ) = _wrap(subCalls);
        _serializeJson(targets, values, calldatas, chainIds2, description);
    }
}
