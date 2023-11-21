// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "../../test/external/MockANGLE.sol";
import "../../contracts/interfaces/IveANGLE.sol";
import "test/external/VyperDeployer.sol";
import "../Utils.s.sol";

function deployMockANGLE() returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _contractName = "MockANGLE";
    string memory _symbol = "mANGLE";
    _constructorParams = abi.encode(_contractName, _symbol);
    _address = address(new MockANGLE(_contractName, _symbol));
}

// Deploy through remix for testnet deploys. See README.
function deployVeANGLE(
    VyperDeployer vyperDeployer,
    address _mockANGLE
) returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _contractName = "veANGLE";
    _constructorParams = abi.encode(_mockANGLE, _contractName, "1");
    _address = address(vyperDeployer.deployContract(_contractName, _constructorParams));
}

contract DeployTestANGLE is Utils {
    function run() external returns (address _address, bytes memory _constructorParams, string memory _contractName) {
        (_address, _constructorParams, _contractName) = deployMockANGLE();
    }
}
