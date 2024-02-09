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
import "stringutils/strings.sol";

contract CheckRoles is Utils {
    using strings for *;

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

    string public constant OUTPUT_PATH = "./scripts/roles.json";
    string private json;
    uint256 private jsonIndex;
    string private output;
    string private outputActor;
    string private jsonActor;
    uint256 private jsonActorIndex;

    // TODO also check that all proxy contracts have been initialized
    function run() external {
        vm.label(oldDeployer, "Old Deployer");
        vm.label(oldKeeper, "Old Keeper");
        vm.label(oldKeeperPolygon, "Old Keeper Polygon");
        vm.label(oldKeeperPolygon2, "Old Keeper Polygon 2");
        vm.label(merklKeeper, "Merkl Keeper");

        string memory jsonGlobal = "chain";
        uint256[] memory chainIds = vm.envUint("CHAIN_IDS", ",");
        string memory finalOutput;
        for (uint256 i = 0; i < chainIds.length; i++) {
            json = vm.toString(chainIds[i]);
            jsonIndex = 0;
            output = "";
            _checkRoles(chainIds[i]);
            finalOutput = vm.serializeString(jsonGlobal, vm.toString(chainIds[i]), output);
        }
        vm.writeFile(OUTPUT_PATH, finalOutput);
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

                if (!_authorizedCore(chainId, address(transmuterEUR.accessControlManager()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "Transmuter EUR - wrong access control manager: ",
                            vm.toString(address(transmuterEUR.accessControlManager()))
                        )
                    );
                    jsonIndex++;
                }
                if (!_authorizedCore(chainId, address(transmuterUSD.accessControlManager()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "Transmuter USD - wrong access control manager: ",
                            vm.toString(address(transmuterUSD.accessControlManager()))
                        )
                    );
                    jsonIndex++;
                }
                if (!_authorizedMinter(chainId, angle.minter())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Angle - minter role: ", vm.toString(angle.minter()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, proposalSender.owner())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Proposal Sender - owner: ", vm.toString(proposalSender.owner()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedCoreMerkl(chainId, address(merklMiddleman.accessControlManager()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "Merkl Middleman - wrong access control manager: ",
                            vm.toString(address(merklMiddleman.accessControlManager()))
                        )
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, gaugeController.admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Gauge Controller - admin role: ", vm.toString(gaugeController.admin()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, gaugeController.future_admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "Gauge Controller - future admin role: ",
                            vm.toString(gaugeController.future_admin())
                        )
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, smartWalletWhitelist.admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Smart Wallet Whitelist - admin: ", vm.toString(smartWalletWhitelist.admin()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, smartWalletWhitelist.future_admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "Smart Wallet Whitelist - future admin: ",
                            vm.toString(smartWalletWhitelist.future_admin())
                        )
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, veAngle.admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("veANGLE - admin: ", vm.toString(veAngle.admin()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, veAngle.future_admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("veANGLE - future admin: ", vm.toString(veAngle.future_admin()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, veBoostProxy.admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("veBoostProxy - admin: ", vm.toString(veBoostProxy.admin()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedOwner(chainId, veBoostProxy.future_admin())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("veBoostProxy - future admin: ", vm.toString(veBoostProxy.future_admin()))
                    );
                    jsonIndex++;
                }
            } else {
                ProposalReceiver proposalReceiver = ProposalReceiver(
                    payable(_chainToContract(chainId, ContractType.ProposalReceiver))
                );
                if (!_authorizedOwner(chainId, proposalReceiver.owner())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Proposal Receiver - owner: ", vm.toString(proposalReceiver.owner()))
                    );
                    jsonIndex++;
                }
            }

            if (_isCoreChain(chainId)) {
                IAccessControlCore angleRouter = IAccessControlCore(
                    _chainToContract(chainId, ContractType.AngleRouter)
                );
                if (!_authorizedCore(chainId, angleRouter.core())) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Angle Router - core: ", vm.toString(angleRouter.core()))
                    );
                    jsonIndex++;
                }
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
                if (!_authorizedCoreMerkl(chainId, address(distributionCreator.core()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Distribution creator - wrong core: ", vm.toString(distributionCreator.core()))
                    );
                    jsonIndex++;
                }
                if (!_authorizedCoreMerkl(chainId, address(distributor.core()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat("Distributor - wrong core: ", vm.toString(distributor.core()))
                    );
                    jsonIndex++;
                }
            }

            if (_isSavingsDeployed(chainId)) {
                ISavings stEUR = ISavings(_chainToContract(chainId, ContractType.StEUR));
                ISavings stUSD = ISavings(_chainToContract(chainId, ContractType.StUSD));
                if (!_authorizedCore(chainId, address(stEUR.accessControlManager()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "StEUR - wrong access control manager: ",
                            vm.toString(stEUR.accessControlManager())
                        )
                    );
                    jsonIndex++;
                }
                if (!_authorizedCore(chainId, address(stUSD.accessControlManager()))) {
                    output = vm.serializeString(
                        json,
                        vm.toString(jsonIndex),
                        string.concat(
                            "StUSD - wrong access control manager: ",
                            vm.toString(stUSD.accessControlManager())
                        )
                    );
                    jsonIndex++;
                }
            }

            ProxyAdmin proxyAdmin = ProxyAdmin(_chainToContract(chainId, ContractType.ProxyAdmin));

            if (!_authorizedProxyAdminOwner(chainId, proxyAdmin.owner())) {
                output = vm.serializeString(
                    json,
                    vm.toString(jsonIndex),
                    string.concat("Proxy Admin - owner: ", vm.toString(proxyAdmin.owner()))
                );
                jsonIndex++;
            }
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
            outputActor = "";
            jsonActor = vm.toString(listAddressToCheck[i]);
            jsonActorIndex = 0;
            address actor = listAddressToCheck[i];
            if (agEUR.isMinter(actor) && !_authorizedMinter(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "AgEUR - minter role");
                jsonActorIndex++;
            }
            if (agUSD.isMinter(actor) && !_authorizedMinter(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "AgUSD - minter role");
                jsonActorIndex++;
            }
            if (core.hasRole(GOVERNOR_ROLE, actor) && !_authorizedGovernor(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "Core Borrow - governor role");
                jsonActorIndex++;
            }
            if (core.hasRole(GUARDIAN_ROLE, actor) && !_authorizedGuardian(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "Core Borrow - guardian role");
                jsonActorIndex++;
            }
            if (core.hasRole(FLASHLOANER_TREASURY_ROLE, actor) && !_authorizedFlashloaner(chainId, actor)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    "Core Borrow - flashloan role"
                );
                jsonActorIndex++;
            }
            if (timelock.hasRole(PROPOSER_ROLE, actor) && !_authorizedProposer(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "Timelock - proposer role");
                jsonActorIndex++;
            }
            if (timelock.hasRole(CANCELLER_ROLE, actor) && !_authorizedCanceller(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "Timelock - canceller role");
                jsonActorIndex++;
            }
            if (timelock.hasRole(EXECUTOR_ROLE, actor) && !_authorizedExecutor(chainId, actor)) {
                outputActor = vm.serializeString(jsonActor, vm.toString(jsonActorIndex), "Timelock - executor role");
                jsonActorIndex++;
            }
            if (timelock.hasRole(DEFAULT_ADMIN_ROLE, actor) && !_authorizeDefaultAdmin(chainId, actor)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    "Timelock - default admin role"
                );
                jsonActorIndex++;
            }

            if (_revertOnWrongFunctioCall(chainId))
                for (uint256 j = 0; j < allContracts.length; j++)
                    _checkAddressAccessControl(chainId, IGenericAccessControl(allContracts[j]), actor);

            if (_isMerklDeployed(chainId)) {
                CoreBorrow coreMerkl = CoreBorrow(_chainToContract(chainId, ContractType.CoreMerkl));
                if (coreMerkl.hasRole(GOVERNOR_ROLE, actor) && !_authorizedGovernor(chainId, actor)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        "Core Merkl - governor role"
                    );
                    jsonActorIndex++;
                }
                if (coreMerkl.hasRole(GUARDIAN_ROLE, actor) && !_authorizedGuardian(chainId, actor)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        "Core Merkl - guardian role"
                    );
                    jsonActorIndex++;
                }
                // No one should have this role
                if (coreMerkl.hasRole(FLASHLOANER_TREASURY_ROLE, actor)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        "Core Merkl - flashloan role"
                    );
                    jsonActorIndex++;
                }
            }

            if (chainId == CHAIN_ETHEREUM) {
                IAccessControl angleDistributor = IAccessControl(
                    _chainToContract(chainId, ContractType.AngleDistributor)
                );
                if (angleDistributor.hasRole(GOVERNOR_ROLE, actor) && !_authorizedGovernor(chainId, actor)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        "Angle distributor - governor role"
                    );
                    jsonActorIndex++;
                }
                if (angleDistributor.hasRole(GUARDIAN_ROLE, actor) && !_authorizedGuardian(chainId, actor)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        "Angle distributor - guardian role"
                    );
                    jsonActorIndex++;
                }
            }
            if (outputActor.toSlice().len() != 0)
                output = vm.serializeString(json, vm.toString(listAddressToCheck[i]), outputActor);
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
        if (token.canonicalToken() != _chainToContract(chainId, contractType)) {
            outputActor = vm.serializeString(
                jsonActor,
                vm.toString(jsonActorIndex),
                string.concat(nameToken, "  - wrong canonical token: ", vm.toString(token.canonicalToken()))
            );
            jsonActorIndex++;
        }
        if (contractType == ContractType.Angle) {
            if (!_authorizedCore(chainId, token.coreBorrow())) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(nameToken, "  - wrong core borrow: ", vm.toString(token.coreBorrow()))
                );
                jsonActorIndex++;
            }
        } else {
            if (token.treasury() != _chainToContract(chainId, contractTypeTreasury)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(nameToken, "  - wrong treasury: ", vm.toString(token.treasury()))
                );
                jsonActorIndex++;
            }
        }
        if (token.lzEndpoint() != address(_lzEndPoint(chainId))) {
            outputActor = vm.serializeString(
                jsonActor,
                vm.toString(jsonActorIndex),
                string.concat(nameToken, "  - wrong endpoint: ", vm.toString(token.lzEndpoint()))
            );
            jsonActorIndex++;
        }
    }

    function _checkVaultManagers(uint256 chainId, ContractType treasuryType) internal {
        ITreasury treasury = ITreasury(_chainToContract(chainId, treasuryType));
        uint256 i;
        while (true) {
            try treasury.vaultManagerList(i) returns (address vault) {
                if (address(IVaultManager(vault).treasury()) != address(treasury)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        string.concat(
                            IERC721Metadata(vault).name(),
                            "Vault Manager - wrong treasury: ",
                            vm.toString(address(treasury))
                        )
                    );
                    jsonActorIndex++;
                }
                i++;
            } catch {
                break;
            }
        }
    }

    function _checkGlobalAccessControl(uint256 chainId, IGenericAccessControl contractToCheck) public {
        try contractToCheck.owner() returns (address owner) {
            if (!_authorizedOwner(chainId, owner)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " owner: ", vm.toString(owner))
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.minter() returns (address minter) {
            if (!_authorizedOwner(chainId, minter)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " minter: ", vm.toString(minter))
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.treasury() returns (address treasury) {
            if (!_authorizedTreasury(chainId, treasury)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " treasury: ", vm.toString(treasury))
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.coreBorrow() returns (address coreBorrow) {
            if (!_authorizedCore(chainId, coreBorrow)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " core borrow: ", vm.toString(coreBorrow))
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.core() returns (address coreBorrow) {
            if (!_authorizedCore(chainId, coreBorrow)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " core borrow: ", vm.toString(coreBorrow))
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.admin() returns (address admin) {
            if (!_authorizedOwner(chainId, admin)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " admin: ", vm.toString(admin))
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.future_admin() returns (address future_admin) {
            if (!_authorizedOwner(chainId, future_admin)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " future admin: ", vm.toString(future_admin))
                );
                jsonActorIndex++;
            }
        } catch {}
    }

    function _checkAddressAccessControl(
        uint256 chainId,
        IGenericAccessControl contractToCheck,
        address addressToCheck
    ) public {
        try contractToCheck.isMinter(addressToCheck) returns (bool isMinter) {
            if (isMinter && !_authorizedMinter(chainId, addressToCheck)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " minter: ")
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.isTrusted(addressToCheck) returns (bool isTrusted) {
            if (isTrusted && !_authorizedTrusted(chainId, addressToCheck)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " trusted: ")
                );
                jsonActorIndex++;
            }
        } catch {}
        try contractToCheck.trusted(addressToCheck) returns (uint256 isTrusted) {
            if (isTrusted > 0 && !_authorizedTrusted(chainId, addressToCheck)) {
                outputActor = vm.serializeString(
                    jsonActor,
                    vm.toString(jsonActorIndex),
                    string.concat(vm.toString(address(contractToCheck)), " trusted: ")
                );
                jsonActorIndex++;
            }
        } catch {}
        bytes32[] memory listRoles = _listRoles();
        for (uint256 i = 0; i < listRoles.length; i++) {
            try contractToCheck.hasRole(listRoles[i], addressToCheck) returns (bool hasRole) {
                if (hasRole && !_mapCheckRoles(i, chainId, addressToCheck)) {
                    outputActor = vm.serializeString(
                        jsonActor,
                        vm.toString(jsonActorIndex),
                        string.concat(vm.toString(address(contractToCheck)), " have role: ", _nameRoles(i))
                    );
                    jsonActorIndex++;
                }
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
