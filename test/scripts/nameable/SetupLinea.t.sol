// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ScriptHelpers } from "../ScriptHelpers.t.sol";
import "../../../scripts/Constants.s.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";

contract SetupLineaTest is ScriptHelpers {
    using stdJson for string;
    mapping(uint256 => address) private _chainToToken;

    function setUp() public override {
        super.setUp();
    }

    function testScript() external {
        uint256[] memory chainIds = _executeProposal();
        vm.selectFork(forkIdentifier[59144]);

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

        assertEq(ITreasuryGovernance(treasuryUSD).core(), 0x4b1E2c2762667331Bc91648052F646d1b0d35984);
        assertEq(IGenericAccessControl(0x0000206329b97DB379d5E1Bf586BbDB969C63274).isMinter(stUSD), true);
        assertEq(IERC20Metadata(stUSD).name(), nameUSD);
        assertEq(IERC20Metadata(stUSD).symbol(), symbolUSD);
        assertEq(ISavings(stUSD).maxRate(), maxRateUSD);
        assertEq(ISavings(stUSD).isTrustedUpdater(keeper), 1);

        assertEq(ITreasuryGovernance(treasuryEUR).core(), 0x4b1E2c2762667331Bc91648052F646d1b0d35984);
        assertEq(IGenericAccessControl(0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8).isMinter(stEUR), true);
        assertEq(IERC20Metadata(stEUR).name(), nameEUR);
        assertEq(IERC20Metadata(stEUR).symbol(), symbolEUR);
        assertEq(ISavings(stEUR).maxRate(), maxRateEUR);
        assertEq(ISavings(stEUR).isTrustedUpdater(keeper), 1);

        address EURA = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;
        address USDA = 0x0000206329b97DB379d5E1Bf586BbDB969C63274;

        assertEq(IERC20Metadata(EURA).name(), "EURA");
        assertEq(IERC20Metadata(EURA).symbol(), "EURA");
        console.log(IERC20Metadata(EURA).totalSupply());

        assertEq(IERC20Metadata(USDA).name(), "USDA");
        assertEq(IERC20Metadata(USDA).symbol(), "USDA");
        console.log(IERC20Metadata(USDA).totalSupply());
    }
}
