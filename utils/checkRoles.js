const { Client, GatewayIntentBits, EmbedBuilder } = require("discord.js");
const { registry, ChainId, Transmuter__factory, ANGLE__factory, ProposalSender__factory, GaugeController__factory, SmartWalletWhitelist__factory, VeANGLE__factory, VeBoostProxy__factory, MerklGaugeMiddleman__factory, AngleRouter__factory, Distributor__factory, DistributionCreator__factory, Savings__factory, AgTokenSideChainMultiBridge__factory, VaultManager__factory, Treasury__factory, AngleRouterPolygon__factory, ProxyAdmin__factory, AgToken__factory, CoreBorrow__factory, Timelock__factory } = require('@angleprotocol/sdk');
const { ethers } = require("ethers");

let actors = {};
let roles = [];
let listAddressToCheck = [];


/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CONSTANTS                                                    
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const GOVERNOR_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GOVERNOR_ROLE"));

const GUARDIAN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GUARDIAN_ROLE"));
const FLASHLOANER_TREASURY_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("FLASHLOANER_TREASURY_ROLE"));
const TIMELOCK_ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TIMELOCK_ADMIN_ROLE"));
const PROPOSER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("PROPOSER_ROLE"));
const EXECUTOR_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("EXECUTOR_ROLE"));
const CANCELLER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("CANCELLER_ROLE"));
const KEEPER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("KEEPER_ROLE"));
const DISTRIBUTOR_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("DISTRIBUTOR_ROLE"));
const DEFAULT_ADMIN_ROLE = ethers.constants.HashZero;

const _isMerklDeployed = (chainRegistry) => {
  return chainRegistry.Merkl.CoreMerkl && chainRegistry.Merkl.DistributionCreator && chainRegistry.Merkl.Distributor;
}

const _isAngleDeployed = (chainRegistry) => {
  return chainRegistry.ANGLE != undefined;
}

const _isCoreChain = (chainRegistry) => {
  return chainRegistry.CoreBorrow != undefined;
}

const _isSavingsDeployed = (chainRegistry) => {
  return chainRegistry.EUR.Savings && chainRegistry.USD.Savings;
}

const _revertOnWrongFunctionCall = (chainId) => {
  return chainId != ChainId.CELO;
}

const _mapCheckRoles = (index, chainId, addressToCheck) => {
  switch (index) {
    case 0: {
      return _authorizedGovernor(chainId, chainRegistry, addressToCheck);
    }
    case 1: {
      return _authorizedGuardian(chainId, chainRegistry, addressToCheck);
    }
    case 2: {
      return _authorizedFlashloaner(chainRegistry, addressToCheck);
    }
    case 3: {
      return _authorizedTimelockAdmin(chainRegistry, addressToCheck);
    }
    case 4: {
      return _authorizedProposer(chainId, chainRegistry, addressToCheck);
    }
    case 5: {
      return _authorizedExecutor(chainRegistry, addressToCheck);
    }
    case 6: {
      return _authorizedCanceller(chainRegistry, addressToCheck);
    }
    case 7: {
      return _authorizedKeeper(chainRegistry, addressToCheck);
    }
    case 8: {
      return _authorizedDistributor(chainId, chainRegistry, addressToCheck);
    }
    case 9: {
      return _authorizeDefaultAdmin(chainRegistry, addressToCheck);
    }
  }
}

const _nameRoles = (role) => {
  switch (role) {
    case GOVERNOR_ROLE: {
      return "GOVERNOR";
    }
    case GUARDIAN_ROLE: {
      return "GUARDIAN";
    }
    case FLASHLOANER_TREASURY_ROLE: {
      return "FLASHLOANER_TREASURY";
    }
    case TIMELOCK_ADMIN_ROLE: {
      return "TIMELOCK_ADMIN";
    }
    case PROPOSER_ROLE: {
      return "PROPOSER";
    }
    case EXECUTOR_ROLE: {
      return "EXECUTOR";
    }
    case CANCELLER_ROLE: {
      return "CANCELLER";
    }
    case KEEPER_ROLE: {
      return "KEEPER";
    }
    case DISTRIBUTOR_ROLE: {
      return "DISTRIBUTOR";
    }
    case DEFAULT_ADMIN_ROLE: {
      return "DEFAULT_ADMIN";
    }
  }
}

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CHECKS                                                    
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const _checkAddressAccessControl = async (chainId, chainRegistry, contractToCheck, addressToCheck) => {
  try {
    const [isMinter] = await callReadOnlyFunction(contractToCheck, [addressToCheck], "isMinter", ["address"], ["bool"]);
    if (isMinter && !_authorizedMinter(chainRegistry, addressToCheck)) {
      if (actors.hasOwnProperty(addressToCheck)) {
        actors[addressToCheck].push(`${contractToCheck} - minter role`);
      } else {
        actors[addressToCheck] = [`${contractToCheck} - minter role`];
      }
    }
  } catch (error) {}
  try {
    const [isTrusted] = await callReadOnlyFunction(contractToCheck, [addressToCheck], "isTrusted", ["address"], ["bool"]);
    if (isTrusted && !_authorizedTrusted(chainId, chainRegistry, addressToCheck)) {
      if (actors.hasOwnProperty(addressToCheck)) {
        actors[addressToCheck].push(`${contractToCheck} - trusted role`);
      } else {
        actors[addressToCheck] = [`${contractToCheck} - trusted role`];
      }
    }
  } catch (error) {}
  try {
    const [isTrusted] = await callReadOnlyFunction(contractToCheck, [addressToCheck], "trusted", ["address"], ["uint256"]);
    if (isTrusted > 0 && !_authorizedTrusted(chainId, chainRegistry, addressToCheck)) {
      if (actors.hasOwnProperty(addressToCheck)) {
        actors[addressToCheck].push(`${contractToCheck} - trusted role`);
      } else {
        actors[addressToCheck] = [`${contractToCheck} - trusted role`];
      }
    }
  } catch (error) {}
    const roles = [GOVERNOR_ROLE, GUARDIAN_ROLE, FLASHLOANER_TREASURY_ROLE, TIMELOCK_ADMIN_ROLE, PROPOSER_ROLE, EXECUTOR_ROLE, CANCELLER_ROLE, KEEPER_ROLE, DISTRIBUTOR_ROLE, DEFAULT_ADMIN_ROLE];
    for (const role of roles) {
      try {
        const [hasRole] = await callReadOnlyFunction(contractToCheck, [role, addressToCheck], "hasRole", ["bytes32", "address"], ["bool"]);
        if (hasRole && !_mapCheckRoles(i, chainId, addressToCheck)) {
          if (actors.hasOwnProperty(addressToCheck)) {
            actors[addressToCheck].push(`${contractToCheck} have role: ${_nameRoles(role)}`);
          } else {
            actors[addressToCheck] = [`${contractToCheck} have role: ${_nameRoles(role)}`];
          }
        }
  } catch (error) {}
    }
}

const _checkOnLzToken = async (chainRegistery, token, type) => {
  switch (type) {
    case "EUR": {
      const [canonicalToken] = await callReadOnlyFunction(token, [], "canonicalToken", [], ["address"]);
      if (canonicalToken != chainRegistery.EUR.AgToken) {
        roles.push(`EURA - wrong canonical token: ${canonicalToken}`);
      }
      if (await token.treasury() != chainRegistery.EUR.Treasury) {
        roles.push(`EURA - wrong treasury: ${await token.treasury()}`);
      }
      break;
    }
    case "USD": {
      const [canonicalToken] = await callReadOnlyFunction(token, [], "canonicalToken", [], ["address"]);
      if (canonicalToken != chainRegistery.USD.AgToken) {
        roles.push(`USDA - wrong canonical token: ${canonicalToken}`);
      }
      if (await token.treasury() != chainRegistery.USD.Treasury) {
        roles.push(`USDA - wrong treasury: ${await token.treasury()}`);
      }
      break;
    }
    case "ANGLE": {
      const [canonicalToken] = await callReadOnlyFunction(token, [], "canonicalToken", [], ["address"]);
      if (canonicalToken != chainRegistery.ANGLE) {
        roles.push(`ANGLE - wrong canonical token: ${canonicalToken}`);
      }
      const [coreBorrow] = await callReadOnlyFunction(token, [], "coreBorrow", [], ["address"]);
      if (!_authorizedCore(chainRegistery, coreBorrow)) {
        roles.push(`ANGLE - wrong core borrow: ${coreBorrow}`);
      }
      break;
    }
  }
  // TODO: Add the rest once we have a reliable way to get the endpoint
  // if (token.lzEndpoint() != address(_lzEndPoint(chainId))) {
  //   outputActor = vm.serializeString(
  //       jsonActor,
  //       vm.toString(jsonActorIndex),
  //       string.concat(nameToken, "  - wrong endpoint: ", vm.toString(token.lzEndpoint()))
  //   );
  //   jsonActorIndex++;
  // }
};
 
const _checkVaultManagers = async (provider, treasuryAddress) => {
  let i = 0;
  const treasury = Treasury__factory.connect(treasuryAddress, provider);
  while (true) {
    try {
      const vault = VaultManager__factory.connect(await treasury.vaultManagerList(i), provider);
      if (treasury.address != await vault.treasury()) {
        roles.push(`Treasury - wrong treasury: ${vault.treasury()}`);
      }
    } catch (error) {
    }
    break;
  }
}

async function callReadOnlyFunction(contract, params, functionName, functionParamsTypes, functionReturnType) {
  const functionSignature = `${functionName}(${functionParamsTypes.join(",")})`;


  const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
const data = iface.encodeFunctionData(functionName, params);

const provider = contract.provider;

const result = await provider.call({
  to: contract.address,
  data
})

  // Decode the result, if necessary
  const decodedResult = ethers.utils.defaultAbiCoder.decode(functionReturnType, result);

  return decodedResult;
}

const _checkGlobalAccessControl = async (chainRegistry, globalAccessControl) => {
  try {
    const [owner] = await callReadOnlyFunction(globalAccessControl, [], "owner", [], ["bool"]);
  if (!_authorizedOwner(chainRegistry, owner)) {
    roles.push(`Global Access Control - wrong owner: ${owner}`);
  }
  } catch (error) {
  }
  try {
  const [minter] = await callReadOnlyFunction(globalAccessControl, [], "minter", [], ["address"]);
  if (!_authorizedOwner(chainRegistry, minter)) {
    roles.push(`Global Access Control - wrong minter: ${minter}`);
  }
} catch (error) {
}
  try {
  const [treasury] = await callReadOnlyFunction(globalAccessControl, [], "treasury", [], ["address"]);
  if (!_authorizedTreasury(chainRegistry, treasury)) {
    roles.push(`Global Access Control - wrong treasury: ${treasury}`);
  }
} catch (error) {
}
  try {
  const [coreBorrow] = await callReadOnlyFunction(globalAccessControl, [], "coreBorrow", [], ["address"]);
  if (!_authorizedCore(chainRegistry, coreBorrow)) {
    roles.push(`Global Access Control - wrong core borrow: ${coreBorrow}`);
  }
} catch (error) {
}
  try {
  const [core] = await callReadOnlyFunction(globalAccessControl, [], "core", [], ["address"]);
  if (!_authorizedCore(chainRegistry, core)) {
    roles.push(`Global Access Control - wrong core: ${core}`);
  }
} catch (error) {
}
  try {
  const [admin] = await callReadOnlyFunction(globalAccessControl, [], "admin", [], ["address"]);
  if (!_authorizedOwner(chainRegistry, admin)) {
    roles.push(`Global Access Control - wrong admin: ${admin}`);
  }
} catch (error) {
}
  try {
  const [futureAdmin] = await callReadOnlyFunction(globalAccessControl, [], "future_admin", [], ["address"]);
  if (!_authorizedOwner(chainRegistry, futureAdmin)) {
    roles.push(`Global Access Control - wrong future admin: ${futureAdmin}`);
  }
} catch (error) {
}
}


/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const _authorizedCore = (chainRegistry, core) => {
  return core == chainRegistry.CoreBorrow;
}

const _authorizedMinter = (chainRegistry, minter) => {
  return !minter || minter == chainRegistry.Governor || minter == chainRegistry.Timelock;
}

const _authorizedOwner = (chainId, chainRegistry, owner) => {
  return !owner || owner == chainRegistry.Governor || owner == chainRegistry.Timelock || owner == chainRegistry.ProxyAdmin || owner == chainRegistry.CoreBorrow || (chainId == ChainId.MAINNET && owner == chainRegistry.AngleGovernor);
}

const _authorizedGovernor = (chainId, chainRegistry, governor) => {
  return !governor ||  chainRegistry.Governor || governor == chainRegistry.Timelock || owner == chainRegistry.ProxyAdmin || owner == chainRegistry.CoreBorrow || (chainId == ChainId.MAINNET && governor == chainRegistry.AngleGovernor);
}

const _authorizedGuardian = (chainId, chainRegistry, guardian) => {
  return !guardian || guardian == chainRegistry.Governor || guardian == chainRegistry.Guardian || guardian == chainRegistry.Timelock || guardian == chainRegistry.ProxyAdmin || guardian == chainRegistry.CoreBorrow || (chainId == ChainId.MAINNET && guardian == chainRegistry.AngleGovernor);
}

const _authorizedCoreMerkl = (chainRegistry, core) => {
  return core == chainRegistry.Merkl.CoreMerkl;
}

const _authorizedFlashloaner = (chainRegistry, flashloaner) => {
  return !flashloaner || flashloaner == chainRegistry.EUR.Treasury || flashloaner == chainRegistry.USD.Treasury;
}

const _authorizedProposer = (chainId, chainRegistry, proposer) => {
  return chainId == ChainId.MAINNET ? proposer == chainRegistry.AngleGovernor : proposer == chainRegistry.ProposalReceiver;
}

const _authorizedExecutor = (chainRegistry, executor) => {
  return executor == chainRegistry.Guardian;
}

const _authorizedCanceller = (chainRegistry, canceller) => {
  return canceller == chainRegistry.Guardian;
}

const _authorizedTimelockAdmin = (chainRegistry, admin) => {
  return false;
}

const _authorizeDefaultAdmin = (chainRegistry, admin) => {
  return false;
}

const _authorizedKeeper = (chainRegistry, keeper) => {
  return false;
}

const _authorizedTrusted = (chainid, chainRegistry, trusted) => {
  return trusted == chainRegistry.Governor || trusted == chainRegistry.Guardian || trusted == chainRegistry.Timelock || trusted == chainRegistry.ProxyAdmin || trusted == chainRegistry.CoreBorrow || chainId == ChainId.MAINNET && trusted == chainRegistry.AngleGovernor;
}

const _authorizedDistributor = (chainId, chainRegistry, distributor) => {
  return chainId == ChainId.MAINNET && distributor == chainRegistry.AngleDistributor;
}

const _authorizedProxyAdminOwner = (chainRegistry, owner) => {
  return owner == chainRegistry.Governor;
}

const _authorizedTreasury = (chainRegistry, treasury) => {
  return treasury == chainRegistry.EUR.Treasury || treasury == chainRegistry.USD.Treasury;
}

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        MAIN                                                     
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const getURIFromChainId = (chainId) => {
  switch (chainId) {
    case 1:
      return process.env.ETH_NODE_URI_MAINNET;
    case 42161:
      return process.env.ETH_NODE_URI_ARBITRUM;
    case 137:
      return process.env.ETH_NODE_URI_POLYGON;
    case 100:
      return process.env.ETH_NODE_URI_GNOSIS;
    case 43114:
      return process.env.ETH_NODE_URI_AVALANCHE;
    case 8453:
      return process.env.ETH_NODE_URI_FANTOM;
    case 56:
      return process.env.ETH_NODE_URI_BSC;
    case 42220:
      return process.env.ETH_NODE_URI_CELO;
    case 1101:
      return process.env.ETH_NODE_URI_POLYGON_ZKEVM;
    case 10:
      return process.env.ETH_NODE_URI_OPTIMISM;
    case 59144:
      return process.env.ETH_NODE_URI_LINEA;
  };
};

// Function to get all addresses from the registry
function getAllAddresses(registry) {
  let addresses = [];

  for (let key in registry) {
    if (typeof registry[key] === 'object' && registry[key] !== null) {
      // If the value is a nested object, recursively get addresses
      addresses = addresses.concat(getAllAddresses(registry[key]));
    } else if (ethers.utils.isAddress(registry[key])) {
      // If the value is not an object, assume it's an address and add to the list
      addresses.push(ethers.utils.getAddress(registry[key])?.toString());
    }
  }

  return addresses;
}

const checkRoles = async () => {
  const chainIds = process.env.CHAIN_IDS.split(",").map((chainId) => parseInt(chainId));

  for (const chainId of chainIds) {
    const chainRegistry = registry(chainId);
    const provider = new ethers.providers.JsonRpcProvider(getURIFromChainId(chainId));
    const allContracts = await getAllAddresses(chainRegistry);

    const govMultisig = chainRegistry.Governor;
    const guardianMultisig = chainRegistry.Guardian;
    const timelock = chainRegistry.Timelock;
    const coreBorrow = chainRegistry.CoreBorrow;
    const proxyAdmin = chainRegistry.ProxyAdmin;
    const oldDeployer = "0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185";
    const oldKeeper = "0xcC617C6f9725eACC993ac626C7efC6B96476916E";
    const oldKeeperPolygon = "0x5EB715d601C2F27f83Cb554b6B36e047822fB70a";
    const oldKeeperPolygon2 = "0xEd42E58A303E20523A695CB31ac31df26C50397B";
    const merklKeeper = "0x435046800Fb9149eE65159721A92cB7d50a7534b";

    listAddressToCheck = [oldDeployer, oldKeeper, oldKeeperPolygon, oldKeeperPolygon2, merklKeeper, govMultisig, guardianMultisig, timelock, coreBorrow, proxyAdmin];
    if (chainId == ChainId.MAINNET) {
      const angleGovernor = chainRegistry.AngleGovernor;
      listAddressToCheck.push(angleGovernor);
    }

    if (chainId == ChainId.MAINNET) {
      const transmuterEUR = Transmuter__factory.connect(chainRegistry.EUR.Transmuter, provider);
      const transmuterUSD = Transmuter__factory.connect(chainRegistry.USD.Transmuter, provider);
      const angle = ANGLE__factory.connect(chainRegistry.ANGLE, provider);
      const proposalSender = ProposalSender__factory.connect(chainRegistry.ProposalSender, provider);
      const gaugeController = GaugeController__factory.connect(chainRegistry.GaugeController, provider);
      const smartWalletWhitelist = SmartWalletWhitelist__factory.connect(chainRegistry.SmartWalletWhitelist, provider);
      const veANGLE = VeANGLE__factory.connect(chainRegistry.veANGLE, provider);
      const veBoostProxy = VeBoostProxy__factory.connect(chainRegistry.veBoostProxy, provider);
      const merklMiddleman = MerklGaugeMiddleman__factory.connect(chainRegistry.MerklGaugeMiddleman, provider);

      if (!_authorizedCore(chainRegistry, await transmuterEUR.accessControlManager())) {
        roles.push(`Transmuter EUR - wrong access control manager: ${await transmuterEUR.accessControlManager()}`);
      }
      if (!_authorizedCore(chainRegistry, await transmuterUSD.accessControlManager())) {
        roles.push(`Transmuter USD - wrong access control manager: ${await transmuterUSD.accessControlManager()}`);
      }
      if (!_authorizedMinter(chainRegistry, await angle.minter())) {
        roles.push(`Angle - minter role: ${await angle.minter()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await proposalSender.owner())) {
        roles.push(`Proposal Sender - owner: ${await proposalSender.owner()}`);
      }
      if (!_authorizedCoreMerkl(chainRegistry, await merklMiddleman.accessControlManager())) {
        roles.push(`Merkl Middleman - wrong access control manager: ${await merklMiddleman.accessControlManager()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await gaugeController.admin())) {
        roles.push(`Gauge Controller - admin role: ${await gaugeController.admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await gaugeController.future_admin())) {
        roles.push(`Gauge Controller - future admin role: ${await gaugeController.future_admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await smartWalletWhitelist.admin())) {
        roles.push(`Smart Wallet Whitelist - admin: ${await smartWalletWhitelist.admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await smartWalletWhitelist.future_admin())) {
        roles.push(`Smart Wallet Whitelist - future admin: ${await smartWalletWhitelist.future_admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await veANGLE.admin())) {
        roles.push(`veANGLE - admin: ${await veANGLE.admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await veANGLE.future_admin())) {
        roles.push(`veANGLE - future admin: ${await veANGLE.future_admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await veBoostProxy.admin())) {
        roles.push(`veBoostProxy - admin: ${await veBoostProxy.admin()}`);
      }
      if (!_authorizedOwner(chainId, chainRegistry, await veBoostProxy.future_admin())) {
        roles.push(`veBoostProxy - future admin: ${await veBoostProxy.future_admin()}`);
      }
    } else {
      const proposalReceiver = ProposalSender__factory.connect(chainRegistry.ProposalReceiver, provider);

      if (!_authorizedOwner(chainId, chainRegistry, await proposalReceiver.owner())) {
        roles.push(`Proposal Receiver - owner: ${await proposalReceiver.owner()}`);
      }
    }

    if (_isCoreChain(chainRegistry)) {
      const angleRouter = AngleRouterPolygon__factory.connect(chainRegistry.AngleRouterV2, provider);
      if (!_authorizedCore(chainRegistry, await angleRouter.core())) {
        roles.push(`Angle Router - core: ${await angleRouter.core()}`);
      }
    }

    if (_isAngleDeployed(chainRegistry) && chainId != ChainId.POLYGON) {
      await _checkOnLzToken(chainRegistry, AgTokenSideChainMultiBridge__factory.connect(chainRegistry.bridges.LayerZero, provider), "ANGLE");
    }

    if (_isMerklDeployed(chainRegistry)) {
      const distributionCreator = DistributionCreator__factory.connect(chainRegistry.Merkl.DistributionCreator, provider);
      const distributor = Distributor__factory.connect(chainRegistry.Merkl.Distributor, provider);

      if (!_authorizedCoreMerkl(chainRegistry, await distributionCreator.core())) {
        roles.push(`Distribution Creator - wrong core: ${await distributionCreator.core()}`);
      }
      if (!_authorizedCoreMerkl(chainRegistry, await distributor.core())) {
        roles.push(`Distributor - wrong core: ${await distributor.core()}`);
      }
    }

    if (_isSavingsDeployed(chainRegistry)) {
      const savingsEUR = Savings__factory.connect(chainRegistry.EUR.Savings, provider);
      const savingsUSD = Savings__factory.connect(chainRegistry.USD.Savings, provider);

      if (!_authorizedCore(chainRegistry, await savingsEUR.accessControlManager())) {
        roles.push(`Savings EUR - wrong access control manager:  ${await savingsEURaccessControlManager()}`);
      }
      if (!_authorizedCore(chainRegistry, await savingsUSD.accessControlManager())) {
        roles.push(`Savings USD - wrong access control manager:  ${await savingsUSDaccessControlManager()}`);
      }
    }

    const proxyAdminContract = ProxyAdmin__factory.connect(proxyAdmin, provider);
    if (!_authorizedProxyAdminOwner(chainRegistry, await proxyAdminContract.owner())) {
      roles.push(`Proxy Admin - owner: ${await proxyAdminContract.owner()}`);
    }
    await _checkOnLzToken(chainRegistry, AgTokenSideChainMultiBridge__factory.connect(chainRegistry.EUR.bridges.LayerZero, provider), "EUR");
    await _checkOnLzToken(chainRegistry, AgTokenSideChainMultiBridge__factory.connect(chainRegistry.USD.bridges.LayerZero, provider), "USD");
    await _checkVaultManagers(provider, chainRegistry.EUR.Treasury);
    await _checkVaultManagers(provider, chainRegistry.USD.Treasury);

    if (_revertOnWrongFunctionCall(chainId)) {
      for (const contract of allContracts) {
        const contractInstance = new ethers.Contract(contract, [], provider);
        _checkGlobalAccessControl(chainRegistry, contractInstance);
      }
    }

    // Contract to check roles on
    const EURA = AgToken__factory.connect(chainRegistry.EUR.AgToken, provider);
    const USDA = AgToken__factory.connect(chainRegistry.USD.AgToken, provider);
    const core = CoreBorrow__factory.connect(coreBorrow, provider);
    const timelockContract = Timelock__factory.connect(timelock, provider); 

    for (const actor of listAddressToCheck) {
      const [isMinterEUR] = await callReadOnlyFunction(EURA, [actor], "isMinter", ["address"], ["bool"]);
      if (isMinterEUR && !_authorizedMinter(chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("EURA - minter role");
        } else {
          actors[actor] = ["EURA - minter role"];
        }
      }
      const [isMinterUSD] = await callReadOnlyFunction(USDA, [actor], "isMinter", ["address"], ["bool"]);
      if (isMinterUSD && !_authorizedMinter(chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("USDA - minter role");
        } else {
          actors[actor] = ["USDA - minter role"];
        }
      }
      const [hasRoleGovernor] = await callReadOnlyFunction(core, [GOVERNOR_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleGovernor && !_authorizedGovernor(chainId, chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - governor role");
        } else {
          actors[actor] = ["Timelock - governor role"];
        }
      }
      const [hasRoleGuardian] = await callReadOnlyFunction(core, [GUARDIAN_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleGuardian && !_authorizedGuardian(chainId, chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - guardian role");
        } else {
          actors[actor] = ["Timelock - guardian role"];
        }
      }
      const [hasRoleFlashloaner] = await callReadOnlyFunction(core, [FLASHLOANER_TREASURY_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleFlashloaner && !_authorizedFlashloaner(chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - flashloaner role");
        } else {
          actors[actor] = ["Timelock - flashloaner role"];
        }
      }
      const [hasRoleProposer] = await callReadOnlyFunction(timelockContract, [PROPOSER_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleProposer && !_authorizedProposer(chainId, chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - proposer role");
        } else {
          actors[actor] = ["Timelock - proposer role"];
        }
      }
      const [hasRoleExecutor] = await callReadOnlyFunction(timelockContract, [EXECUTOR_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleExecutor && !_authorizedExecutor(chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - executor role");
        } else {
          actors[actor] = ["Timelock - executor role"];
        }
      }
      const [hasRoleCanceller] = await callReadOnlyFunction(timelockContract, [CANCELLER_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleCanceller && !_authorizedCanceller(chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - canceller role");
        } else {
          actors[actor] = ["Timelock - canceller role"];
        }
      }
      const [hasRoleDefaultAdmin] = await callReadOnlyFunction(timelockContract, [DEFAULT_ADMIN_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
      if (hasRoleDefaultAdmin && !_authorizeDefaultAdmin(chainRegistry, actor)) {
        if (actors.hasOwnProperty(actor)) {
          actors[actor].push("Timelock - default admin role");
        } else {
          actors[actor] = ["Timelock - default admin role"];
        }
      }

      if (_revertOnWrongFunctionCall(chainId)) {
        for (const contractToCheck of allContracts) {
          const instance = new ethers.Contract(contractToCheck, [], provider);
          await _checkAddressAccessControl(chainId, chainRegistry, instance, actor);
        }
      }

      if (_isMerklDeployed(chainRegistry)) {
        const coreMerkl = CoreBorrow__factory.connect(chainRegistry.Merkl.CoreMerkl, provider);
        const [hasRoleGovernor] = await callReadOnlyFunction(coreMerkl, [GOVERNOR_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
        if (hasRoleGovernor && !_authorizedGovernor(chainId, chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Merkl Core - governor role");
          } else {
            actors[actor] = ["Merkl Core - governor role"];
          }
        }
        const [hasRoleGuardian] = await callReadOnlyFunction(coreMerkl, [GUARDIAN_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
        if (hasRoleGuardian && !_authorizedGuardian(chainId, chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Merkl Core - guardian role");
          } else {
            actors[actor] = ["Merkl Core - guardian role"];
          }
        }
        const [hasRoleFlashloaner] = await callReadOnlyFunction(coreMerkl, [FLASHLOANER_TREASURY_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
        if (hasRoleFlashloaner) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Merkl Core - flashloaner role");
          } else {
            actors[actor] = ["Merkl Core - flashloaner role"];
          }
        }
      }

      if (chainId == ChainId.MAINNET) {
        const distributor = Distributor__factory.connect(chainRegistry.AngleDistributor, provider);
        const [hasRoleGovernor] = await callReadOnlyFunction(distributor, [GOVERNOR_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
        if (hasRoleGovernor && !_authorizedGovernor(chainId, chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Angle Distributor - governor role");
          } else {
            actors[actor] = ["Angle Distributor - governor role"];
          }
        }
        const [hasRoleGuardian] = await callReadOnlyFunction(distributor, [GUARDIAN_ROLE, actor], "hasRole", ["bytes32", "address"], ["bool"]);
        if (hasRoleGuardian && !_authorizedGuardian(chainId, chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Angle Distributor - guardian role");
          } else {
            actors[actor] = ["Angle Distributor - guardian role"];
          }
        }
      }
    }



  }
  console.log(roles, actors);
};

/*
const getChannel = (discordClient, channelName) => {
  return discordClient.channels.cache.find(
    (channel) => channel.name === channelName
  );
};

const isDecimal = (s) => {
  s = s.toString();
  var regex = /^[0-9]*\.?[0-9]+$/;
  return regex.test(s) && !isNaN(parseFloat(s)) && isFinite(s);
}

const rolesChannel = "roles-on-chain";

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages],
});

client.on("ready", async () => {
  console.log(`Logged in as ${client.user.tag}!`);


  const channel = getChannel(client, rolesChannel);
  if (!channel) {
    console.log("discord channel not found");
    return;
  }

  const content = readFileSync("./scripts/roles.json");
  const roles = JSON.parse(content);
  const chains = Object.keys(roles);
  let embeds = [];
  await Promise.all(
    chains.map(async (chain) => {
      const title = `⛓️ Chain: ${chain}`;
      const keys = Object.keys(roles[chain]);
      let message = "";
      await Promise.all(
        keys.map(async (key) => {
          if (!isDecimal(key)) {
            message += `\n👨‍🎤 **Actor: ${key}**\n`;
            const actorKeys = Object.keys(roles[chain][key]);
            await Promise.all(
              actorKeys.map((actorKey) => {
                message += `${roles[chain][key][actorKey].toString()}\n`;
              })
            );
          } else {
            message += `${roles[chain][key]}\n`;
          }
        })
      );
      embeds.push(new EmbedBuilder().setTitle(title).setDescription(message));
    })
  );

  const lastMessages = (
    await channel.messages.fetch({ limit: 20, sort: "timestamp" })
  )
    .map((m) => m.embeds)
    .flat();
  const latestChainIdsMessages = chains
    .map((chain) => lastMessages.find((m) => m?.title == `⛓️ Chain: ${chain}`))
    .filter((m) => m);
  for (const embed of embeds) {
    if (
      latestChainIdsMessages.find(
        (m) =>
          m.data.description.replace(/\n/g, "") ==
          embed.data.description.replace(/\n/g, "")
      )
    ) {
      console.log("chain embed is already the same");
      continue;
    } else {
      console.log(
        "chain embed does not exist or isn't the same",
        embed.data.title
      );
      await channel.send({ embeds: [embed] });
    }
  }
  process.exit(0);
});

client.login(process.env.DISCORD_TOKEN);

*/

(async () => {
  await checkRoles();
})();