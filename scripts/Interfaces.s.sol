pragma solidity ^0.8.19;

interface IVaultManagerGovernance {
    function setUint64(uint64 param, bytes32 what) external;

    function interestRate() external view returns (uint64);
}

interface ISavings {
    function setRate(uint208 newRate) external;

    function rate() external view returns (uint208);
}

interface IAngle {
    function setMinter(address minter) external;
}

interface IVeAngle {
    function commit_transfer_ownership(address newAdmin) external;

    function apply_transfer_ownership() external;
}

interface IGaugeController {
    function commit_transfer_ownership(address newAdmin) external;

    function apply_transfer_ownership() external;
}

interface ILiquidityGauge {
    function commit_transfer_ownership(address newAdmin) external;

    function apply_transfer_ownership() external;
}

interface IVeBoost {
    function commit_transfer_ownership(address newAdmin) external;

    function apply_transfer_ownership() external;
}

interface IVeBoostProxy {
    function commit_admin(address newAdmin) external;

    function apply_transfer_ownership() external;
}

interface ISmartWalletWhitelist {
    function commitAdmin(address newAdmin) external;

    function applyAdmin() external;
}

interface IFeeDistributor {
    function commit_admin(address newAdmin) external;

    function accept_admin() external;
}
