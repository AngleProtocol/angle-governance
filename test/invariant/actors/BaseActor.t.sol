// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IERC20} from "oz-v5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "oz-v5/token/ERC20/extensions/IERC20Metadata.sol";
import {Test, stdMath, StdStorage, stdStorage} from "forge-std/Test.sol";
import {IVotes} from "oz-v5/governance/utils/IVotes.sol";
import {AngleGovernor} from "contracts/AngleGovernor.sol";
import "contracts/utils/Errors.sol";

struct TestStorage {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 amountOut;
}

contract BaseActor is Test {
    address public constant sweeper = address(uint160(uint256(keccak256(abi.encodePacked("sweeper")))));
    uint256 internal _minWallet = 0; // in base 18
    uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18

    mapping(bytes32 => uint256) public calls;
    mapping(address => uint256) public addressToIndex;
    address[] public actors;
    uint256 public nbrActor;
    address internal _currentActor;

    IERC20 public angle;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(_currentActor, _currentActor);
        _;
        vm.stopPrank();
    }

    constructor(uint256 _nbrActor, string memory actorType, IERC20 _angle) {
        for (uint256 i; i < _nbrActor; ++i) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", actorType, i)))));
            actors.push(actor);
            addressToIndex[actor] = i;
        }
        nbrActor = _nbrActor;
        angle = _angle;
    }
}
