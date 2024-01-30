// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { IVaultManager } from "borrow/interfaces/IVaultManager.sol";
import { ITreasury } from "borrow/interfaces/ITreasury.sol";
import { IAgToken } from "borrow/interfaces/IAgToken.sol";
import { IERC721Metadata } from "oz/token/ERC721/extensions/IERC721Metadata.sol";
import { IAccessControl } from "oz/access/IAccessControl.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";
import { TimelockControllerWithCounter } from "contracts/TimelockControllerWithCounter.sol";
import { Utils } from "../Utils.s.sol";
import "../Constants.s.sol";

contract CheckRoles is Utils {
    address constant oldDeployer = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185;
    address constant oldKeeper = 0xcC617C6f9725eACC993ac626C7efC6B96476916E;
    address constant oldKeeperPolygon = 0x5EB715d601C2F27f83Cb554b6B36e047822fB70a;
    address constant oldKeeperPolygon2 = 0xEd42E58A303E20523A695CB31ac31df26C50397B;
    address constant merklKeeper = 0x435046800Fb9149eE65159721A92cB7d50a7534b;
    address constant tmpCoreBorrowUSD = 0x3fc5a1bd4d0A435c55374208A6A81535A1923039;
    string constant angleLZ = "Angle LZ";

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant FLASHLOANER_TREASURY_ROLE = keccak256("FLASHLOANER_TREASURY_ROLE");
    bytes32 public constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    address[] public allContracts;

    // TODO also check that all proxy contracts have been initialized
    function run() external {
        vm.label(oldDeployer, "Old Deployer");
        vm.label(oldKeeper, "Old Keeper");
        vm.label(oldKeeperPolygon, "Old Keeper Polygon");
        vm.label(oldKeeperPolygon2, "Old Keeper Polygon 2");
        vm.label(merklKeeper, "Merkl Keeper");

        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        for (uint256 i = 0; i < chainIds.length; i++) {
            console.log("############  Chain ID: ", chainIds[i], " ############");
            _checkRoles(chainIds[i]);
        }
    }

    function _checkRoles(uint256 chainId) public {
        vm.selectFork(forkIdentifier[chainId]);

        allContracts = _getAllContracts(chainId);
        // Address to check roles for
        uint256 nbrActors = chainId == CHAIN_ETHEREUM ? 11 : 10;
        address[] memory listAddressToCheck = new address[](nbrActors);

        {
            address govMultisig = _chainToContract(chainId, ContractType.GovernorMultisig);
            address guardianMultisig = _chainToContract(chainId, ContractType.GuardianMultisig);
            address timelock = _chainToContract(chainId, ContractType.Timelock);
            address coreBorrow = _chainToContract(chainId, ContractType.CoreBorrow);
            address proxyAdmin = _chainToContract(chainId, ContractType.ProxyAdmin);

            vm.label(govMultisig, "Governor Multisig");
            vm.label(guardianMultisig, "Guardian Multisig");
            vm.label(timelock, "Timelock");
            vm.label(coreBorrow, "Core Borrow");
            vm.label(proxyAdmin, "Proxy Admin");

            listAddressToCheck[0] = oldDeployer;
            listAddressToCheck[1] = oldKeeper;
            listAddressToCheck[2] = oldKeeperPolygon;
            listAddressToCheck[3] = oldKeeperPolygon2;
            listAddressToCheck[4] = merklKeeper;
            listAddressToCheck[5] = govMultisig;
            listAddressToCheck[6] = guardianMultisig;
            listAddressToCheck[7] = timelock;
            listAddressToCheck[8] = coreBorrow;
            listAddressToCheck[9] = proxyAdmin;
            if (chainId == CHAIN_ETHEREUM) listAddressToCheck[10] = _chainToContract(chainId, ContractType.Governor);
        }

        {
            // It would be better with a try catch but I don't know how why it doesn't work
            if (chainId == CHAIN_ETHEREUM) {
                // Contract to check roles on
                ITransmuter transmuterEUR = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgEUR));
                ITransmuter transmuterUSD = ITransmuter(_chainToContract(chainId, ContractType.TransmuterAgUSD));
                IAngle angle = IAngle(_chainToContract(chainId, ContractType.Angle));
                ProposalSender proposalSender = ProposalSender(
                    payable(_chainToContract(chainId, ContractType.ProposalSender))
                );
                IGaugeController gaugeController = IGaugeController(
                    _chainToContract(chainId, ContractType.GaugeController)
                );
                ISmartWalletWhitelist smartWalletWhitelist = ISmartWalletWhitelist(
                    _chainToContract(chainId, ContractType.SmartWalletWhitelist)
                );
                IVeAngle veAngle = IVeAngle(_chainToContract(chainId, ContractType.veANGLE));
                IVeBoostProxy veBoostProxy = IVeBoostProxy(_chainToContract(chainId, ContractType.veBoostProxy));
                IGenericAccessControl merklMiddleman = IGenericAccessControl(
                    _chainToContract(chainId, ContractType.MerklMiddleman)
                );

                if (!_authorizedCore(chainId, address(transmuterEUR.accessControlManager())))
                    console.log(
                        "Transmuter EUR - wrong access control manager: ",
                        address(transmuterEUR.accessControlManager())
                    );
                if (!_authorizedCore(chainId, address(transmuterUSD.accessControlManager())))
                    console.log(
                        "Transmuter USD - wrong access control manager: ",
                        address(transmuterUSD.accessControlManager())
                    );
                if (!_authorizedMinter(chainId, angle.minter())) console.log("Angle - minter role: ", angle.minter());
                if (!_authorizedOwner(chainId, proposalSender.owner()))
                    console.log("Proposal Sender - owner: ", proposalSender.owner());
                if (!_authorizedCoreMerkl(chainId, address(merklMiddleman.accessControlManager())))
                    console.log(
                        "Merkl Middleman - wrong access control manager: ",
                        address(merklMiddleman.accessControlManager())
                    );
                if (!_authorizedOwner(chainId, gaugeController.admin()))
                    console.log("Gauge Controller - admin role: ", gaugeController.admin());
                if (!_authorizedOwner(chainId, gaugeController.future_admin()))
                    console.log("Gauge Controller - future admin role: ", gaugeController.future_admin());
                if (!_authorizedOwner(chainId, smartWalletWhitelist.admin()))
                    console.log("Smart Wallet Whitelist - admin: ", smartWalletWhitelist.admin());
                if (!_authorizedOwner(chainId, smartWalletWhitelist.future_admin()))
                    console.log("Smart Wallet Whitelist - future admin: ", smartWalletWhitelist.future_admin());
                if (!_authorizedOwner(chainId, veAngle.admin())) console.log("veANGLE - admin: ", veAngle.admin());
                if (!_authorizedOwner(chainId, veAngle.future_admin()))
                    console.log("veANGLE - future admin: ", veAngle.future_admin());
                if (!_authorizedOwner(chainId, veBoostProxy.admin()))
                    console.log("veBoostProxy - admin: ", veBoostProxy.admin());
                if (!_authorizedOwner(chainId, veBoostProxy.future_admin()))
                    console.log("veBoostProxy - future admin: ", veBoostProxy.future_admin());
            } else {
                ProposalReceiver proposalReceiver = ProposalReceiver(
                    payable(_chainToContract(chainId, ContractType.ProposalReceiver))
                );
                if (!_authorizedOwner(chainId, proposalReceiver.owner()))
                    console.log("Proposal Receiver - owner: ", proposalReceiver.owner());
            }

            if (_isCoreChain(chainId)) {
                IAccessControlCore angleRouter = IAccessControlCore(
                    _chainToContract(chainId, ContractType.AngleRouter)
                );
                if (!_authorizedCore(chainId, angleRouter.core()))
                    console.log("Angle Router - core: ", angleRouter.core());
            }

            if (_isAngleDeployed(chainId) && chainId != CHAIN_POLYGON)
                _checkOnLZToken(
                    chainId,
                    ILayerZeroBridge(_chainToContract(chainId, ContractType.AngleLZ)),
                    angleLZ,
                    ContractType.Angle,
                    ContractType.TreasuryAgEUR
                );

            if (_isMerklDeployed(chainId)) {
                IAccessControlCore distributionCreator = IAccessControlCore(
                    _chainToContract(chainId, ContractType.DistributionCreator)
                );
                IAccessControlCore distributor = IAccessControlCore(
                    _chainToContract(chainId, ContractType.Distributor)
                );
                if (!_authorizedCoreMerkl(chainId, address(distributionCreator.core())))
                    console.log("Distribution creator - wrong core: ", distributionCreator.core());
                if (!_authorizedCoreMerkl(chainId, address(distributor.core())))
                    console.log("Distributor - wrong core: ", distributor.core());
            }

            if (_isSavingsDeployed(chainId)) {
                ISavings stEUR = ISavings(_chainToContract(chainId, ContractType.StEUR));
                ISavings stUSD = ISavings(_chainToContract(chainId, ContractType.StUSD));
                if (!_authorizedCore(chainId, address(stEUR.accessControlManager())))
                    console.log("StEUR - wrong access control manager: ", stEUR.accessControlManager());
                if (!_authorizedCore(chainId, address(stUSD.accessControlManager())))
                    console.log("StUSD - wrong access control manager: ", stUSD.accessControlManager());
            }

            ProxyAdmin proxyAdmin = ProxyAdmin(_chainToContract(chainId, ContractType.ProxyAdmin));

            if (!_authorizedProxyAdminOwner(chainId, proxyAdmin.owner()))
                console.log("Proxy Admin - owner: ", proxyAdmin.owner());
            _checkOnLZToken(
                chainId,
                ILayerZeroBridge(_chainToContract(chainId, ContractType.AgEURLZ)),
                "AgEUR LZ",
                ContractType.AgEUR,
                ContractType.TreasuryAgEUR
            );
            _checkOnLZToken(
                chainId,
                ILayerZeroBridge(_chainToContract(chainId, ContractType.AgUSDLZ)),
                "AgUSD LZ",
                ContractType.AgUSD,
                ContractType.TreasuryAgUSD
            );
            _checkVaultManagers(chainId, ContractType.TreasuryAgEUR);
            _checkVaultManagers(chainId, ContractType.TreasuryAgUSD);

            if (_revertOnWrongFunctioCall(chainId))
                for (uint256 i = 0; i < allContracts.length; i++)
                    _checkGlobalAccessControl(chainId, IGenericAccessControl(allContracts[i]));
        }

        // Contract to check roles on
        IAgToken agEUR = IAgToken(_chainToContract(chainId, ContractType.AgEUR));
        IAgToken agUSD = IAgToken(_chainToContract(chainId, ContractType.AgUSD));
        CoreBorrow core = CoreBorrow(_chainToContract(chainId, ContractType.CoreBorrow));
        TimelockControllerWithCounter timelock = TimelockControllerWithCounter(
            payable(_chainToContract(chainId, ContractType.Timelock))
        );
        for (uint256 i = 0; i < listAddressToCheck.length; i++) {
            address actor = listAddressToCheck[i];
            console.log("======== Actor: ", actor, " =========");

            if (agEUR.isMinter(actor) && !_authorizedMinter(chainId, actor)) console.log("AgEUR - minter role");
            if (agUSD.isMinter(actor) && !_authorizedMinter(chainId, actor)) console.log("AgUSD - minter role");
            if (core.hasRole(GOVERNOR_ROLE, actor) && !_authorizedGovernor(chainId, actor))
                console.log("Core Borrow - governor role");
            if (core.hasRole(GUARDIAN_ROLE, actor) && !_authorizedGuardian(chainId, actor))
                console.log("Core Borrow - guardian role");
            if (core.hasRole(FLASHLOANER_TREASURY_ROLE, actor) && !_authorizedFlashloaner(chainId, actor))
                console.log("Core Borrow - flashloan role");
            if (timelock.hasRole(PROPOSER_ROLE, actor) && !_authorizedProposer(chainId, actor))
                console.log("Timelock - proposer role");
            if (timelock.hasRole(CANCELLER_ROLE, actor) && !_authorizedCanceller(chainId, actor))
                console.log("Timelock - canceller role");
            if (timelock.hasRole(EXECUTOR_ROLE, actor) && !_authorizedExecutor(chainId, actor))
                console.log("Timelock - executor role");
            if (timelock.hasRole(DEFAULT_ADMIN_ROLE, actor) && !_authorizeDefaultAdmin(chainId, actor))
                console.log("Timelock - default admin role");

            if (_revertOnWrongFunctioCall(chainId))
                for (uint256 j = 0; j < allContracts.length; j++)
                    _checkAddressAccessControl(chainId, IGenericAccessControl(allContracts[j]), actor);

            if (_isMerklDeployed(chainId)) {
                CoreBorrow coreMerkl = CoreBorrow(_chainToContract(chainId, ContractType.CoreMerkl));
                if (coreMerkl.hasRole(GOVERNOR_ROLE, actor) && !_authorizedGovernor(chainId, actor))
                    console.log("Core Merkl - governor role");
                if (coreMerkl.hasRole(GUARDIAN_ROLE, actor) && !_authorizedGuardian(chainId, actor))
                    console.log("Core Merkl - guardian role");
                // No one should have this role
                if (coreMerkl.hasRole(FLASHLOANER_TREASURY_ROLE, actor)) console.log("Core Merkl - flashloan role");
            }

            if (chainId == CHAIN_ETHEREUM) {
                IAccessControl angleDistributor = IAccessControl(
                    _chainToContract(chainId, ContractType.AngleDistributor)
                );
                if (angleDistributor.hasRole(GOVERNOR_ROLE, actor) && !_authorizedGovernor(chainId, actor))
                    console.log("Angle distributor - governor role");
                if (angleDistributor.hasRole(GUARDIAN_ROLE, actor) && !_authorizedGuardian(chainId, actor))
                    console.log("Angle distributor - guardian role");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CHECKS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _checkOnLZToken(
        uint256 chainId,
        ILayerZeroBridge token,
        string memory nameToken,
        ContractType contractType,
        ContractType contractTypeTreasury
    ) internal returns (bool) {
        if (token.canonicalToken() != _chainToContract(chainId, contractType))
            console.log(string.concat(nameToken, "  - wrong canonical token: ", vm.toString(token.canonicalToken())));
        if (contractType == ContractType.Angle) {
            if (!_authorizedCore(chainId, token.coreBorrow()))
                console.log(string.concat(nameToken, "  - wrong core borrow: ", vm.toString(token.coreBorrow())));
        } else {
            if (token.treasury() != _chainToContract(chainId, contractTypeTreasury))
                console.log(string.concat(nameToken, "  - wrong treasury: ", vm.toString(token.treasury())));
        }
        if (token.lzEndPoint() != address(_lzEndPoint(chainId)))
            console.log(string.concat(nameToken, "  - wrong endpoint: ", vm.toString(address(token.lzEndPoint()))));
    }

    function _checkVaultManagers(uint256 chainId, ContractType treasuryType) internal {
        ITreasury treasury = ITreasury(_chainToContract(chainId, treasuryType));
        uint256 i;
        while (true) {
            try treasury.vaultManagerList(i) returns (address vault) {
                if (address(IVaultManager(vault).treasury()) != address(treasury))
                    console.log(
                        string.concat(
                            IERC721Metadata(vault).name(),
                            "Vault Manager - wrong treasury: ",
                            vm.toString(address(treasury))
                        )
                    );
                i++;
            } catch {
                break;
            }
        }
    }

    function _checkGlobalAccessControl(uint256 chainId, IGenericAccessControl contractToCheck) public {
        try contractToCheck.owner() returns (address owner) {
            if (!_authorizedOwner(chainId, owner))
                console.log(vm.toString(address(contractToCheck)), " owner: ", owner);
        } catch {}
        try contractToCheck.minter() returns (address minter) {
            if (!_authorizedOwner(chainId, minter))
                console.log(vm.toString(address(contractToCheck)), " minter: ", minter);
        } catch {}
        try contractToCheck.treasury() returns (address treasury) {
            if (!_authorizedTreasury(chainId, treasury))
                console.log(vm.toString(address(contractToCheck)), " treasury: ", treasury);
        } catch {}
        try contractToCheck.coreBorrow() returns (address coreBorrow) {
            if (!_authorizedCore(chainId, coreBorrow))
                console.log(vm.toString(address(contractToCheck)), " core borrow: ", coreBorrow);
        } catch {}
        try contractToCheck.core() returns (address coreBorrow) {
            if (!_authorizedCore(chainId, coreBorrow))
                console.log(vm.toString(address(contractToCheck)), " core borrow: ", coreBorrow);
        } catch {}
        try contractToCheck.admin() returns (address admin) {
            if (!_authorizedOwner(chainId, admin))
                console.log(vm.toString(address(contractToCheck)), " admin: ", admin);
        } catch {}
        try contractToCheck.future_admin() returns (address future_admin) {
            if (!_authorizedOwner(chainId, future_admin))
                console.log(vm.toString(address(contractToCheck)), " future admin: ", future_admin);
        } catch {}
    }

    function _checkAddressAccessControl(
        uint256 chainId,
        IGenericAccessControl contractToCheck,
        address addressToCheck
    ) public {
        try contractToCheck.isMinter(addressToCheck) returns (bool isMinter) {
            if (isMinter && !_authorizedMinter(chainId, addressToCheck))
                console.log(vm.toString(address(contractToCheck)), " minter: ");
        } catch {}
        try contractToCheck.isTrusted(addressToCheck) returns (bool isTrusted) {
            if (isTrusted && !_authorizedTrusted(chainId, addressToCheck))
                console.log(vm.toString(address(contractToCheck)), " trusted: ");
        } catch {}
        try contractToCheck.trusted(addressToCheck) returns (uint256 isTrusted) {
            if (isTrusted > 0 && !_authorizedTrusted(chainId, addressToCheck))
                console.log(vm.toString(address(contractToCheck)), " trusted: ");
        } catch {}
        bytes32[] memory listRoles = _listRoles();
        for (uint256 i = 0; i < listRoles.length; i++) {
            try contractToCheck.hasRole(listRoles[i], addressToCheck) returns (bool hasRole) {
                if (hasRole && !_mapCheckRoles(i, chainId, addressToCheck))
                    console.log(vm.toString(address(contractToCheck)), " have role: ", _nameRoles(i));
            } catch {}
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTANTS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _listRoles() internal pure returns (bytes32[] memory listRoles) {
        listRoles = new bytes32[](10);
        listRoles[0] = GOVERNOR_ROLE;
        listRoles[1] = GUARDIAN_ROLE;
        listRoles[2] = FLASHLOANER_TREASURY_ROLE;
        listRoles[3] = TIMELOCK_ADMIN_ROLE;
        listRoles[4] = PROPOSER_ROLE;
        listRoles[5] = EXECUTOR_ROLE;
        listRoles[6] = CANCELLER_ROLE;
        listRoles[7] = KEEPER_ROLE;
        listRoles[8] = DISTRIBUTOR_ROLE;
        listRoles[9] = DEFAULT_ADMIN_ROLE;
    }

    function _nameRoles(uint256 index) internal pure returns (string memory nameRole) {
        if (index == 0) return "GOVERNOR";
        if (index == 1) return "GUARDIAN";
        if (index == 2) return "FLASHLOANER_TREASURY";
        if (index == 3) return "TIMELOCK_ADMIN";
        if (index == 4) return "PROPOSER";
        if (index == 5) return "EXECUTOR";
        if (index == 6) return "CANCELLER";
        if (index == 7) return "KEEPER";
        if (index == 8) return "DISTRIBUTOR";
        if (index == 9) return "DEFAULT_ADMIN";
    }

    function _mapCheckRoles(uint256 index, uint256 chainId, address addressToCheck) internal returns (bool) {
        if (index == 0) return _authorizedGovernor(chainId, addressToCheck);
        if (index == 1) return _authorizedGuardian(chainId, addressToCheck);
        if (index == 2) return _authorizedFlashloaner(chainId, addressToCheck);
        if (index == 3) return _authorizedTimelockAdmin(chainId, addressToCheck);
        if (index == 4) return _authorizedProposer(chainId, addressToCheck);
        if (index == 5) return _authorizedExecutor(chainId, addressToCheck);
        if (index == 6) return _authorizedCanceller(chainId, addressToCheck);
        if (index == 7) return _authorizedKeeper(chainId, addressToCheck);
        if (index == 8) return _authorizedDistributor(chainId, addressToCheck);
        if (index == 9) return _authorizeDefaultAdmin(chainId, addressToCheck);
    }

    function _isCoreChain(uint256 chainId) internal pure returns (bool) {
        return
            chainId == CHAIN_ETHEREUM ||
            chainId == CHAIN_ARBITRUM ||
            chainId == CHAIN_AVALANCHE ||
            chainId == CHAIN_OPTIMISM ||
            chainId == CHAIN_POLYGON ||
            chainId == CHAIN_GNOSIS;
    }

    function _isAngleDeployed(uint256 chainId) internal pure returns (bool) {
        return
            chainId == CHAIN_ETHEREUM ||
            chainId == CHAIN_ARBITRUM ||
            chainId == CHAIN_AURORA ||
            chainId == CHAIN_AVALANCHE ||
            chainId == CHAIN_BNB ||
            chainId == CHAIN_FANTOM ||
            chainId == CHAIN_OPTIMISM ||
            chainId == CHAIN_POLYGON;
    }

    function _isMerklDeployed(uint256 chainId) internal pure returns (bool) {
        return
            chainId == CHAIN_ETHEREUM ||
            chainId == CHAIN_ARBITRUM ||
            chainId == CHAIN_AVALANCHE ||
            chainId == CHAIN_BASE ||
            chainId == CHAIN_BNB ||
            chainId == CHAIN_GNOSIS ||
            chainId == CHAIN_LINEA ||
            chainId == CHAIN_MANTLE ||
            chainId == CHAIN_OPTIMISM ||
            chainId == CHAIN_POLYGON ||
            chainId == CHAIN_POLYGONZKEVM;
    }

    function _isSavingsDeployed(uint256 chainId) internal pure returns (bool) {
        return
            chainId == CHAIN_ETHEREUM ||
            chainId == CHAIN_ARBITRUM ||
            chainId == CHAIN_AVALANCHE ||
            chainId == CHAIN_BASE ||
            chainId == CHAIN_BNB ||
            chainId == CHAIN_CELO ||
            chainId == CHAIN_GNOSIS ||
            chainId == CHAIN_OPTIMISM ||
            chainId == CHAIN_POLYGON ||
            chainId == CHAIN_POLYGONZKEVM;
    }

    function _revertOnWrongFunctioCall(uint256 chainId) internal pure returns (bool) {
        return chainId != CHAIN_CELO;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _authorizedOwner(uint256 chainId, address owner) internal returns (bool) {
        return
            owner == address(0) ||
            owner == _chainToContract(chainId, ContractType.GovernorMultisig) ||
            // owner == _chainToContract(chainId, ContractType.GuardianMultisig) ||
            owner == _chainToContract(chainId, ContractType.Timelock) ||
            owner == _chainToContract(chainId, ContractType.CoreBorrow) ||
            owner == _chainToContract(chainId, ContractType.ProxyAdmin) ||
            ((chainId == CHAIN_SOURCE) ? owner == _chainToContract(chainId, ContractType.Governor) : false);
    }

    function _authorizedGovernor(uint256 chainId, address governor) internal returns (bool) {
        return
            governor == address(0) ||
            governor == _chainToContract(chainId, ContractType.GovernorMultisig) ||
            governor == _chainToContract(chainId, ContractType.Timelock) ||
            governor == _chainToContract(chainId, ContractType.CoreBorrow) ||
            governor == _chainToContract(chainId, ContractType.ProxyAdmin) ||
            ((chainId == CHAIN_SOURCE) ? governor == _chainToContract(chainId, ContractType.Governor) : false);
    }

    function _authorizedGuardian(uint256 chainId, address guardian) internal returns (bool) {
        return
            guardian == address(0) ||
            guardian == _chainToContract(chainId, ContractType.GovernorMultisig) ||
            guardian == _chainToContract(chainId, ContractType.GuardianMultisig) ||
            guardian == _chainToContract(chainId, ContractType.Timelock) ||
            guardian == _chainToContract(chainId, ContractType.CoreBorrow) ||
            guardian == _chainToContract(chainId, ContractType.ProxyAdmin) ||
            ((chainId == CHAIN_SOURCE) ? guardian == _chainToContract(chainId, ContractType.Governor) : false);
    }

    /// @notice Vault Managers are also minter
    function _authorizedMinter(uint256 chainId, address minter) internal returns (bool) {
        return
            minter == address(0) ||
            minter == _chainToContract(chainId, ContractType.GovernorMultisig) ||
            minter == _chainToContract(chainId, ContractType.Timelock);
    }

    function _authorizedCore(uint256 chainId, address core) internal returns (bool) {
        // TODO remove tmp core when USD linked to real one
        return core == _chainToContract(chainId, ContractType.CoreBorrow) || core == tmpCoreBorrowUSD;
    }

    function _authorizedCoreMerkl(uint256 chainId, address core) internal returns (bool) {
        return core == _chainToContract(chainId, ContractType.CoreMerkl);
    }

    // TODO need to be fine grained for multiple stablecoins
    function _authorizedFlashloaner(uint256 chainId, address loaner) internal returns (bool) {
        return
            loaner == address(0) ||
            loaner == _chainToContract(chainId, ContractType.TreasuryAgEUR) ||
            loaner == _chainToContract(chainId, ContractType.TreasuryAgUSD);
    }

    function _authorizedProposer(uint256 chainId, address proposer) internal returns (bool) {
        return
            (chainId == CHAIN_SOURCE)
                ? proposer == _chainToContract(chainId, ContractType.Governor)
                : proposer == _chainToContract(chainId, ContractType.ProposalReceiver);
    }

    function _authorizedExecutor(uint256 chainId, address executor) internal returns (bool) {
        return executor == _chainToContract(chainId, ContractType.GuardianMultisig);
    }

    function _authorizedCanceller(uint256 chainId, address canceller) internal returns (bool) {
        return canceller == _chainToContract(chainId, ContractType.GuardianMultisig);
    }

    function _authorizedTimelockAdmin(uint256 chainId, address admin) internal returns (bool) {
        return false;
    }

    function _authorizeDefaultAdmin(uint256 chainId, address admin) internal returns (bool) {
        return false;
    }

    function _authorizedKeeper(uint256 chainId, address keeper) internal returns (bool) {
        // return (
        //     (chainId == CHAIN_POLYGON)
        //         ? (keeper == oldKeeperPolygon || keeper == oldKeeperPolygon2)
        //         : keeper == oldKeeper
        // );
        return false;
    }

    function _authorizedTrusted(uint256 chainId, address trusted) internal returns (bool) {
        return
            trusted == _chainToContract(chainId, ContractType.GovernorMultisig) ||
            trusted == _chainToContract(chainId, ContractType.GuardianMultisig) ||
            trusted == _chainToContract(chainId, ContractType.Timelock) ||
            trusted == _chainToContract(chainId, ContractType.CoreBorrow) ||
            trusted == _chainToContract(chainId, ContractType.ProxyAdmin) ||
            // trusted == oldDeployer ||
            // trusted == oldKeeper ||
            // trusted == oldKeeperPolygon ||
            // trusted == oldKeeperPolygon2 ||
            // trusted == merklKeeper ||
            ((chainId == CHAIN_SOURCE) ? trusted == _chainToContract(chainId, ContractType.Governor) : false);
    }

    function _authorizedDistributor(uint256 chainId, address distributor) internal returns (bool) {
        return
            (chainId == CHAIN_ETHEREUM)
                ? distributor == _chainToContract(chainId, ContractType.AngleDistributor)
                : false;
    }

    function _authorizedProxyAdminOwner(uint256 chainId, address owner) internal returns (bool) {
        return owner == _chainToContract(chainId, ContractType.GovernorMultisig);
    }

    function _authorizedTreasury(uint256 chainId, address treasury) internal returns (bool) {
        return
            treasury == _chainToContract(chainId, ContractType.TreasuryAgEUR) ||
            treasury == _chainToContract(chainId, ContractType.TreasuryAgUSD);
    }
}
