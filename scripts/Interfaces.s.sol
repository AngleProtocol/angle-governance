pragma solidity ^0.8.19;

import { IAccessControl } from "oz/access/IAccessControl.sol";
import { IAccessControlManager } from "interfaces/IAccessControlManager.sol";

interface IAccessControlCore {
    function core() external returns (address);
}

interface IAccessControlViewVyper {
    function admin() external returns (address);

    function future_admin() external returns (address);
}

interface IAccessControlWriteVyper {
    function commit_transfer_ownership(address newAdmin) external;

    function accept_transfer_ownership() external;
}

interface IVaultManagerGovernance {
    function setUint64(uint64 param, bytes32 what) external;

    function interestRate() external view returns (uint64);
}

interface ISavings {
    function setRate(uint208 newRate) external;

    function rate() external view returns (uint208);

    function accessControlManager() external view returns (address);
}

interface IAngle {
    function setMinter(address minter) external;

    function minter() external returns (address);
}

interface IVeAngle is IAccessControlViewVyper, IAccessControlWriteVyper {}

interface IGaugeController is IAccessControlViewVyper, IAccessControlWriteVyper {}

interface ILiquidityGauge is IAccessControlViewVyper, IAccessControlWriteVyper {}

interface IVeBoostProxy is IAccessControlViewVyper, IAccessControlWriteVyper {}

interface ISmartWalletWhitelist is IAccessControlViewVyper {
    function commitAdmin(address newAdmin) external;

    function applyAdmin() external;
}

interface IFeeDistributor is IAccessControlViewVyper {
    function commit_admin(address newAdmin) external;

    function accept_admin() external;
}

interface IGenericAccessControl is IAccessControl, IAccessControlCore, IAccessControlViewVyper {
    function owner() external returns (address);

    function isMinter(address account) external view returns (bool);

    function minter() external view returns (address);

    function treasury() external view returns (address);

    function coreBorrow() external view returns (address);

    function isTrusted(address caller) external view returns (bool);

    function trusted(address caller) external view returns (uint256);

    function accessControlManager() external view returns (address);
}

interface ILayerZeroBridge {
    function canonicalToken() external view returns (address);

    function coreBorrow() external view returns (address);

    function treasury() external view returns (address);

    function lzEndpoint() external view returns (address);
}
