// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "../../test/external/MockANGLE.sol";
import "../../contracts/interfaces/IveANGLE.sol";
import "test/external/VyperDeployer.sol";
import "test/external/SmartWalletChecker.sol";
import "../Utils.s.sol";

interface initVeANGLE {
    function initialize(
        address _admin,
        address _angle,
        address _smartWalletChecker,
        string memory _name,
        string memory _symbol
    ) external;
}

function deployMockANGLE() returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _contractName = "MockANGLE";
    string memory _symbol = "mANGLE";
    _constructorParams = abi.encode(_contractName, _symbol);
    _address = address(new MockANGLE(_contractName, _symbol));
}

function deployVeANGLE(
    VyperDeployer vyperDeployer,
    address _mockANGLE,
    address admin
) returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    address smartWalletChecker = address(new SmartWalletWhitelist(admin));
    _contractName = "veANGLE";
    _constructorParams = abi.encode(_mockANGLE, _contractName, "1");
    _address = address(vyperDeployer.deployContract(_contractName, _constructorParams));
    initVeANGLE(_address).initialize(admin, _mockANGLE, smartWalletChecker, "veANGLE", "veANGLE");
}

contract DeployTestANGLE is Utils {
    function run() external returns (address _address, bytes memory _constructorParams, string memory _contractName) {
        (_address, _constructorParams, _contractName) = deployMockANGLE();
    }
}
