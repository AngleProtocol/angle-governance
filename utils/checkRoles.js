const { Client, GatewayIntentBits, EmbedBuilder } = require("discord.js");
const {
  registry,
  ChainId,
  Transmuter__factory,
  ANGLE__factory,
  ProposalSender__factory,
  GaugeController__factory,
  SmartWalletWhitelist__factory,
  VeANGLE__factory,
  VeBoostProxy__factory,
  MerklGaugeMiddleman__factory,
  Distributor__factory,
  DistributionCreator__factory,
  Savings__factory,
  VaultManager__factory,
  Treasury__factory,
  ProxyAdmin__factory,
  ProposalReceiver__factory,
  AngleRouterV2__factory,
  LayerZeroBridgeToken__factory,
  AccessControl__factory,
} = require("@angleprotocol/sdk");
const { ethers } = require("ethers");
const { createPublicClient, http, getContract } = require("viem");

let actors = {};
let roles = [];
let listAddressToCheck = [];

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CONSTANTS                                                    
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const GOVERNOR_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("GOVERNOR_ROLE")
);

const GUARDIAN_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("GUARDIAN_ROLE")
);
const FLASHLOANER_TREASURY_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("FLASHLOANER_TREASURY_ROLE")
);
const TIMELOCK_ADMIN_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("TIMELOCK_ADMIN_ROLE")
);
const PROPOSER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("PROPOSER_ROLE")
);
const EXECUTOR_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("EXECUTOR_ROLE")
);
const CANCELLER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("CANCELLER_ROLE")
);
const KEEPER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("KEEPER_ROLE")
);
const DISTRIBUTOR_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("DISTRIBUTOR_ROLE")
);
const DEFAULT_ADMIN_ROLE = ethers.constants.HashZero;

const _isMerklDeployed = (chainRegistry) => {
  return (
    chainRegistry.Merkl &&
    chainRegistry.Merkl.CoreMerkl &&
    chainRegistry.Merkl.DistributionCreator &&
    chainRegistry.Merkl.Distributor
  );
};

const _isAngleDeployed = (chainRegistry) => {
  return chainRegistry.ANGLE != undefined;
};

const _isCoreChain = (chainRegistry) => {
  return chainRegistry.CoreBorrow && chainRegistry.AngleRouterV2;
};

const _isSavingsDeployed = (chainRegistry) => {
  return chainRegistry.EUR.Savings && chainRegistry.USD.Savings;
};

const _mapCheckRoles = (index, chainId, chainRegistry, addressToCheck) => {
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
};

const _nameRoles = (index) => {
  switch (index) {
    case 0: {
      return "GOVERNOR";
    }
    case 1: {
      return "GUARDIAN";
    }
    case 2: {
      return "FLASHLOANER_TREASURY";
    }
    case 3: {
      return "TIMELOCK_ADMIN";
    }
    case 4: {
      return "PROPOSER";
    }
    case 5: {
      return "EXECUTOR";
    }
    case 6: {
      return "CANCELLER";
    }
    case 7: {
      return "KEEPER";
    }
    case 8: {
      return "DISTRIBUTOR";
    }
    case 9: {
      return "DEFAULT_ADMIN";
    }
  }
};

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        CHECKS                                                    
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const _checkAddressAccessControl = async (
  chainId,
  chainRegistry,
  contractToCheck,
  addressToCheck
) => {
  const [
    isMinter,
    isTrusted,
    trusted,
    hasRoleGovernor,
    hasRoleGuardian,
    hasRoleFlashloaner,
    hasRoleTimelock,
    hasRoleProposer,
    hasRoleExecutor,
    hasRoleCanceller,
    hasRoleKeeper,
    hasRoleDistributor,
    hasRoleDefaultAdmin,
  ] = await Promise.all([
    safeRead(() => contractToCheck.read.isMinter([addressToCheck])),
    safeRead(() => contractToCheck.read.isTrusted([addressToCheck])),
    safeRead(() => contractToCheck.read.trusted([addressToCheck])),
    safeRead(() =>
      contractToCheck.read.hasRole([GOVERNOR_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([GUARDIAN_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([FLASHLOANER_TREASURY_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([TIMELOCK_ADMIN_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([PROPOSER_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([EXECUTOR_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([CANCELLER_ROLE, addressToCheck])
    ),
    safeRead(() => contractToCheck.read.hasRole([KEEPER_ROLE, addressToCheck])),
    safeRead(() =>
      contractToCheck.read.hasRole([DISTRIBUTOR_ROLE, addressToCheck])
    ),
    safeRead(() =>
      contractToCheck.read.hasRole([DEFAULT_ADMIN_ROLE, addressToCheck])
    ),
  ]);
  if (isMinter && !_authorizedMinter(chainRegistry, addressToCheck)) {
    if (actors.hasOwnProperty(addressToCheck)) {
      actors[addressToCheck].push(`${contractToCheck.address} - minter role`);
    } else {
      actors[addressToCheck] = [`${contractToCheck.address} - minter role`];
    }
  }
  if (
    isTrusted &&
    !_authorizedTrusted(chainId, chainRegistry, addressToCheck)
  ) {
    if (actors.hasOwnProperty(addressToCheck)) {
      actors[addressToCheck].push(`${contractToCheck.address} - trusted role`);
    } else {
      actors[addressToCheck] = [`${contractToCheck.address} - trusted role`];
    }
  }
  if (
    trusted > 0 &&
    !_authorizedTrusted(chainId, chainRegistry, addressToCheck)
  ) {
    if (actors.hasOwnProperty(addressToCheck)) {
      actors[addressToCheck].push(`${contractToCheck.address} - trusted role`);
    } else {
      actors[addressToCheck] = [`${contractToCheck.address} - trusted role`];
    }
  }
  for (const [i, hasRole] of [
    hasRoleGovernor,
    hasRoleGuardian,
    hasRoleFlashloaner,
    hasRoleTimelock,
    hasRoleProposer,
    hasRoleExecutor,
    hasRoleCanceller,
    hasRoleKeeper,
    hasRoleDistributor,
    hasRoleDefaultAdmin,
  ].entries()) {
    if (hasRole && !_mapCheckRoles(i, chainId, chainRegistry, addressToCheck)) {
      if (actors.hasOwnProperty(addressToCheck)) {
        actors[addressToCheck].push(
          `${contractToCheck.address} have role: ${_nameRoles(i)}`
        );
      } else {
        actors[addressToCheck] = [
          `${contractToCheck.address} have role: ${_nameRoles(i)}`,
        ];
      }
    }
  }
};

async function safeRead(operation) {
  try {
    return await operation();
  } catch (error) {
    return null; // Return null or any other value indicating the operation failed
  }
}

const _checkOnLzToken = async (chainRegistery, token, type) => {
  switch (type) {
    case "EUR": {
      const [canonicalToken, treasury] = await Promise.all([
        token.read.canonicalToken(),
        token.read.treasury(),
      ]);
      if (canonicalToken != chainRegistery.EUR.AgToken) {
        roles.push(`EURA - wrong canonical token: ${canonicalToken}`);
      }
      if (treasury != chainRegistery.EUR.Treasury) {
        roles.push(`EURA - wrong treasury: ${treasury}`);
      }
      break;
    }
    case "USD": {
      const [canonicalToken, treasury] = await Promise.all([
        token.read.canonicalToken(),
        token.read.treasury(),
      ]);
      if (canonicalToken != chainRegistery.USD.AgToken) {
        roles.push(`USDA - wrong canonical token: ${canonicalToken}`);
      }
      if (treasury != chainRegistery.USD.Treasury) {
        roles.push(`USDA - wrong treasury: ${treasury}`);
      }
      break;
    }
    case "ANGLE": {
      const [canonicalToken, treasury, coreBorrow] = await Promise.all([
        safeRead(() => token.read.canonicalToken()),
        safeRead(() => token.read.treasury()),
        safeRead(() => token.read.coreBorrow()),
      ]);
      if (canonicalToken != chainRegistery.ANGLE) {
        roles.push(`ANGLE - wrong canonical token: ${canonicalToken}`);
      }
      if (treasury && !_authorizedCore(chainRegistery, treasury)) {
        roles.push(`ANGLE - wrong treasury: ${treasury}`);
      }
      if (coreBorrow && !_authorizedCore(chainRegistery, coreBorrow)) {
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

const _checkVaultManagers = async (client, treasuryAddress) => {
  const BATCH_SIZE = 10; // Adjust based on performance and rate limits
  const treasury = getContract({
    address: treasuryAddress,
    abi: Treasury__factory.abi,
    client,
  });
  let index = 0;
  let hasMore = true;

  while (hasMore) {
    const vaultPromises = [];
    for (let i = 0; i < BATCH_SIZE; i++) {
      const currentIndex = index + i;
      vaultPromises.push(
        treasury.read.vaultManagerList([currentIndex]).catch((error) => {
          hasMore = false; // Stop fetching more batches on error
          return null; // Return null to filter out later
        })
      );
    }

    const vaultAddresses = await Promise.all(vaultPromises);
    const validAddresses = vaultAddresses.filter((address) => address !== null);
    if (validAddresses.length === 0) break; // Exit if no valid addresses were fetched

    const treasuryCheckPromises = validAddresses.map(async (address) => {
      const vault = getContract({
        address,
        abi: VaultManager__factory.abi,
        client,
      });
      const actualTreasury = await vault.read.treasury();
      if (treasury.address !== actualTreasury) {
        roles.push(`Treasury - wrong treasury: ${actualTreasury}`);
      }
    });

    await Promise.all(treasuryCheckPromises);
    index += BATCH_SIZE;
  }
};

const _checkGlobalAccessControl = async (chainRegistry, instance) => {
  const [owner, minter, treasury, coreBorrow, core, admin, futureAdmin] =
    await Promise.all([
      safeRead(() => instance.read.owner()),
      safeRead(() => instance.read.minter()),
      safeRead(() => instance.read.treasury()),
      safeRead(() => instance.read.coreBorrow()),
      safeRead(() => instance.read.core()),
      safeRead(() => instance.read.admin()),
      safeRead(() => instance.read.future_admin()),
    ]);

  if (owner && !_authorizedOwner(chainRegistry, owner)) {
    roles.push(`${instance.address} - wrong owner: ${owner}`);
  }
  if (minter && !_authorizedMinter(chainRegistry, minter)) {
    roles.push(`${instance.address} - wrong minter: ${minter}`);
  }
  if (treasury && !_authorizedTreasury(chainRegistry, treasury)) {
    roles.push(`${instance.address} - wrong treasury: ${treasury}`);
  }
  if (coreBorrow && !_authorizedCore(chainRegistry, coreBorrow)) {
    roles.push(`${instance.address} - wrong core borrow: ${coreBorrow}`);
  }
  if (core && !_authorizedCore(chainRegistry, core)) {
    roles.push(`${instance.address} - wrong core: ${core}`);
  }
  if (admin && !_authorizedOwner(chainRegistry, admin)) {
    roles.push(`${instance.address} - wrong admin: ${admin}`);
  }
  if (futureAdmin && !_authorizedOwner(chainRegistry, futureAdmin)) {
    roles.push(`${instance.address} - wrong future admin: ${futureAdmin}`);
  }
};

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

const _authorizedCore = (chainRegistry, core) => {
  return !core || core == chainRegistry.CoreBorrow;
};

const _authorizedMinter = (chainRegistry, minter) => {
  return (
    !minter ||
    minter == chainRegistry.Governor ||
    minter == chainRegistry.Timelock
  );
};

const _authorizedOwner = (chainId, chainRegistry, owner) => {
  return (
    !owner ||
    owner == chainRegistry.Governor ||
    owner == chainRegistry.Timelock ||
    owner == chainRegistry.ProxyAdmin ||
    owner == chainRegistry.CoreBorrow ||
    (chainId == ChainId.MAINNET && owner == chainRegistry.AngleGovernor)
  );
};

const _authorizedGovernor = (chainId, chainRegistry, governor) => {
  return (
    !governor ||
    chainRegistry.Governor ||
    governor == chainRegistry.Timelock ||
    owner == chainRegistry.ProxyAdmin ||
    owner == chainRegistry.CoreBorrow ||
    (chainId == ChainId.MAINNET && governor == chainRegistry.AngleGovernor)
  );
};

const _authorizedGuardian = (chainId, chainRegistry, guardian) => {
  return (
    !guardian ||
    guardian == chainRegistry.Governor ||
    guardian == chainRegistry.Guardian ||
    guardian == chainRegistry.Timelock ||
    guardian == chainRegistry.ProxyAdmin ||
    guardian == chainRegistry.CoreBorrow ||
    (chainId == ChainId.MAINNET && guardian == chainRegistry.AngleGovernor)
  );
};

const _authorizedCoreMerkl = (chainRegistry, core) => {
  return core == chainRegistry.Merkl.CoreMerkl;
};

const _authorizedFlashloaner = (chainRegistry, flashloaner) => {
  return (
    !flashloaner ||
    flashloaner == chainRegistry.EUR.Treasury ||
    flashloaner == chainRegistry.USD.Treasury
  );
};

const _authorizedProposer = (chainId, chainRegistry, proposer) => {
  return chainId == ChainId.MAINNET
    ? proposer == chainRegistry.AngleGovernor
    : proposer == chainRegistry.ProposalReceiver;
};

const _authorizedExecutor = (chainRegistry, executor) => {
  return executor == chainRegistry.Guardian;
};

const _authorizedCanceller = (chainRegistry, canceller) => {
  return canceller == chainRegistry.Guardian;
};

const _authorizedTimelockAdmin = (chainRegistry, admin) => {
  return false;
};

const _authorizeDefaultAdmin = (chainRegistry, admin) => {
  return false;
};

const _authorizedKeeper = (chainRegistry, keeper) => {
  return false;
};

const _authorizedTrusted = (chainId, chainRegistry, trusted) => {
  return (
    trusted == chainRegistry.Governor ||
    trusted == chainRegistry.Guardian ||
    trusted == chainRegistry.Timelock ||
    trusted == chainRegistry.ProxyAdmin ||
    trusted == chainRegistry.CoreBorrow ||
    (chainId == ChainId.MAINNET && trusted == chainRegistry.AngleGovernor)
  );
};

const _authorizedDistributor = (chainId, chainRegistry, distributor) => {
  return (
    chainId == ChainId.MAINNET && distributor == chainRegistry.AngleDistributor
  );
};

const _authorizedProxyAdminOwner = (chainRegistry, owner) => {
  return owner == chainRegistry.Governor;
};

const _authorizedTreasury = (chainRegistry, treasury) => {
  return (
    treasury == chainRegistry.EUR.Treasury ||
    treasury == chainRegistry.USD.Treasury
  );
};

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
      return process.env.ETH_NODE_URI_BASE;
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
  }
};

// Function to get all addresses from the registry
function getAllAddresses(registry) {
  let addresses = [];

  for (let key in registry) {
    if (typeof registry[key] === "object" && registry[key] !== null) {
      // If the value is a nested object, recursively get addresses
      addresses = addresses.concat(getAllAddresses(registry[key]));
    } else if (ethers.utils.isAddress(registry[key])) {
      // If the value is not an object, assume it's an address and add to the list
      addresses.push(ethers.utils.getAddress(registry[key])?.toString());
    }
  }

  return addresses;
}

const checkRoles = async (chainIds) => {
  const embeds = [];

  await Promise.all(
    chainIds.map(async (chainId) => {
      const chainRegistry = registry(chainId);
      const client = createPublicClient({
        batch: {
          multicall: true,
        },
        cacheTime: 300_000,  // 5 minutes
        chain: chainId,
        transport: http(getURIFromChainId(chainId)),
      });
      const allContracts = await getAllAddresses(chainRegistry);

      const govMultisig = chainRegistry.Governor;
      const guardianMultisig = chainRegistry.Guardian;
      const timelock = chainRegistry.Timelock;
      const coreBorrow = chainRegistry.CoreBorrow;
      const proxyAdmin = chainRegistry.ProxyAdmin;
      const deployer = "0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701";
      const keeper1 = "0xa9bbbDDe822789F123667044443dc7001fb43C01";
      const keeper2 = "0xa9BB7e640FF985376e67bbb5843bF9a63a2fBa02";
      const merklKeeper = "0x435046800Fb9149eE65159721A92cB7d50a7534b";

      listAddressToCheck = [
        deployer,
        keeper1,
        keeper2,
        merklKeeper,
        govMultisig,
        guardianMultisig,
        timelock,
        coreBorrow,
        proxyAdmin,
      ];
      if (chainId == ChainId.MAINNET) {
        const angleGovernor = chainRegistry.AngleGovernor;
        listAddressToCheck.push(angleGovernor);
      }

      if (chainId == ChainId.MAINNET) {
        const transmuterEUR = getContract({
          address: chainRegistry.EUR.Transmuter,
          abi: Transmuter__factory.abi,
          client,
        });
        const transmuterUSD = getContract({
          address: chainRegistry.USD.Transmuter,
          abi: Transmuter__factory.abi,
          client,
        });
        const angle = getContract({
          address: chainRegistry.ANGLE,
          abi: ANGLE__factory.abi,
          client,
        });
        const proposalSender = getContract({
          address: chainRegistry.ProposalSender,
          abi: ProposalSender__factory.abi,
          client,
        });
        const gaugeController = getContract({
          address: chainRegistry.GaugeController,
          abi: GaugeController__factory.abi,
          client,
        });
        const smartWalletWhitelist = getContract({
          address: chainRegistry.SmartWalletWhitelist,
          abi: SmartWalletWhitelist__factory.abi,
          client,
        });
        const veANGLE = getContract({
          address: chainRegistry.veANGLE,
          abi: VeANGLE__factory.abi,
          client,
        });
        const veBoostProxy = getContract({
          address: chainRegistry.veBoostProxy,
          abi: VeBoostProxy__factory.abi,
          client,
        });
        const merklMiddleman = getContract({
          address: chainRegistry.MerklGaugeMiddleman,
          abi: MerklGaugeMiddleman__factory.abi,
          client,
        });

        const [
          eurAccessControlManager,
          usdAccessControlManager,
          angleMinter,
          proposalSenderOwner,
          middlemanAccessControlManager,
          gaugeControllerAdmin,
          gaugeControllerFutureAdmin,
          smartWalletWhitelistAdmin,
          smartWalletWhitelistFutureAdmin,
          veANGLEAdmin,
          veANGLEFutureAdmin,
          veBoostProxyAdmin,
          veBoostProxyFutureAdmin,
        ] = await Promise.all([
          transmuterEUR.read.accessControlManager(),
          transmuterUSD.read.accessControlManager(),
          angle.read.minter(),
          proposalSender.read.owner(),
          merklMiddleman.read.accessControlManager(),
          gaugeController.read.admin(),
          gaugeController.read.future_admin(),
          smartWalletWhitelist.read.admin(),
          smartWalletWhitelist.read.future_admin(),
          veANGLE.read.admin(),
          veANGLE.read.future_admin(),
          veBoostProxy.read.admin(),
          veBoostProxy.read.future_admin(),
        ]);

        if (!_authorizedCore(chainRegistry, eurAccessControlManager)) {
          roles.push(
            `Transmuter EUR - wrong access control manager: ${eurAccessControlManager}`
          );
        }
        if (!_authorizedCore(chainRegistry, usdAccessControlManager)) {
          roles.push(
            `Transmuter USD - wrong access control manager: ${usdAccessControlManager}`
          );
        }
        if (!_authorizedMinter(chainRegistry, angleMinter)) {
          roles.push(`Angle - minter role: ${angleMinter}`);
        }
        if (!_authorizedOwner(chainId, chainRegistry, proposalSenderOwner)) {
          roles.push(`Proposal Sender - owner: ${proposalSenderOwner}`);
        }
        if (
          !_authorizedCoreMerkl(chainRegistry, middlemanAccessControlManager)
        ) {
          roles.push(
            `Merkl Middleman - wrong access control manager: ${middlemanAccessControlManager}`
          );
        }
        if (!_authorizedOwner(chainId, chainRegistry, gaugeControllerAdmin)) {
          roles.push(`Gauge Controller - admin role: ${gaugeControllerAdmin}`);
        }
        if (
          !_authorizedOwner(chainId, chainRegistry, gaugeControllerFutureAdmin)
        ) {
          roles.push(
            `Gauge Controller - future admin role: ${gaugeControllerFutureAdmin}`
          );
        }
        if (
          !_authorizedOwner(chainId, chainRegistry, smartWalletWhitelistAdmin)
        ) {
          roles.push(
            `Smart Wallet Whitelist - admin: ${smartWalletWhitelistAdmin}`
          );
        }
        if (
          !_authorizedOwner(
            chainId,
            chainRegistry,
            smartWalletWhitelistFutureAdmin
          )
        ) {
          roles.push(
            `Smart Wallet Whitelist - future admin: ${smartWalletWhitelistFutureAdmin}`
          );
        }
        if (!_authorizedOwner(chainId, chainRegistry, veANGLEAdmin)) {
          roles.push(`veANGLE - admin: ${veANGLEAdmin}`);
        }
        if (!_authorizedOwner(chainId, chainRegistry, veANGLEFutureAdmin)) {
          roles.push(`veANGLE - future admin: ${veANGLEFutureAdmin}`);
        }
        if (!_authorizedOwner(chainId, chainRegistry, veBoostProxyAdmin)) {
          roles.push(`veBoostProxy - admin: ${veBoostProxyAdmin}`);
        }
        if (
          !_authorizedOwner(chainId, chainRegistry, veBoostProxyFutureAdmin)
        ) {
          roles.push(`veBoostProxy - future admin: ${veBoostProxyFutureAdmin}`);
        }
      } else {
        const proposalReceiver = getContract({
          address: chainRegistry.ProposalReceiver,
          abi: ProposalReceiver__factory.abi,
          client,
        });

        const owner = await proposalReceiver.read.owner();
        if (!_authorizedOwner(chainId, chainRegistry, owner)) {
          roles.push(`Proposal Receiver - owner: ${owner}`);
        }
      }

      if (_isCoreChain(chainRegistry)) {
        const angleRouter = getContract({
          address: chainRegistry.AngleRouterV2,
          abi: AngleRouterV2__factory.abi,
          client,
        });
        const core = await angleRouter.read.core();
        if (!_authorizedCore(chainRegistry, core)) {
          roles.push(`Angle Router - core: ${core}`);
        }
      }

      if (_isAngleDeployed(chainRegistry) && chainId != ChainId.POLYGON) {
        const instance = getContract({
          address: chainRegistry.bridges.LayerZero,
          abi: LayerZeroBridgeToken__factory.abi,
          client,
        });
        await _checkOnLzToken(chainRegistry, instance, "ANGLE");
      }

      if (_isMerklDeployed(chainRegistry)) {
        const distributionCreator = getContract({
          address: chainRegistry.Merkl.DistributionCreator,
          abi: DistributionCreator__factory.abi,
          client,
        });
        const distributor = getContract({
          address: chainRegistry.Merkl.Distributor,
          abi: Distributor__factory.abi,
          client,
        });

        const [distributionCreatorCore, distributorCore] = await Promise.all([
          distributionCreator.read.core(),
          distributor.read.core(),
        ]);

        if (!_authorizedCoreMerkl(chainRegistry, distributionCreatorCore)) {
          roles.push(
            `Distribution Creator - wrong core: ${distributionCreatorCore}`
          );
        }
        if (!_authorizedCoreMerkl(chainRegistry, distributorCore)) {
          roles.push(`Distributor - wrong core: ${distributorCore}`);
        }
      }

      if (_isSavingsDeployed(chainRegistry)) {
        const savingsEUR = getContract({
          address: chainRegistry.EUR.Savings,
          abi: Savings__factory.abi,
          client,
        });
        const savingsUSD = getContract({
          address: chainRegistry.USD.Savings,
          abi: Savings__factory.abi,
          client,
        });

        const [eurAccessControlManager, usdAccessControlManager] =
          await Promise.all([
            savingsEUR.read.accessControlManager(),
            savingsUSD.read.accessControlManager(),
          ]);
        if (!_authorizedCore(chainRegistry, eurAccessControlManager)) {
          roles.push(
            `Savings EUR - wrong access control manager: ${eurAccessControlManager}`
          );
        }
        if (!_authorizedCore(chainRegistry, usdAccessControlManager)) {
          roles.push(
            `Savings USD - wrong access control manager: ${usdAccessControlManager}`
          );
        }
      }

      {
        const proxyAdminContract = getContract({
          address: chainRegistry.ProxyAdmin,
          abi: ProxyAdmin__factory.abi,
          client,
        });
        const owner = await proxyAdminContract.read.owner();
        if (!_authorizedProxyAdminOwner(chainRegistry, owner)) {
          roles.push(`Proxy Admin - owner: ${owner}`);
        }
      }
      await Promise.all([
        _checkOnLzToken(
          chainRegistry,
          getContract({
            address: chainRegistry.EUR.bridges.LayerZero,
            abi: LayerZeroBridgeToken__factory.abi,
            client,
          }),
          "EUR"
        ),
        _checkOnLzToken(
          chainRegistry,
          getContract({
            address: chainRegistry.USD.bridges.LayerZero,
            abi: LayerZeroBridgeToken__factory.abi,
            client,
          }),
          "USD"
        ),
        _checkVaultManagers(client, chainRegistry.EUR.Treasury),
        _checkVaultManagers(client, chainRegistry.USD.Treasury),
      ]);

      await Promise.all(
        allContracts.map(async (contractToCheck) => {
          const instance = getContract({
            address: contractToCheck,
            abi: AccessControl__factory.abi,
            client,
          });
          return _checkGlobalAccessControl(chainRegistry, instance);
        })
      );

      // Contract to check roles on
      const EURA = getContract({
        address: chainRegistry.EUR.AgToken,
        abi: AccessControl__factory.abi,
        client,
      });
      const USDA = getContract({
        address: chainRegistry.USD.AgToken,
        abi: AccessControl__factory.abi,
        client,
      });
      const core = getContract({
        address: coreBorrow,
        abi: AccessControl__factory.abi,
        client,
      });
      const timelockContract = getContract({
        address: timelock,
        abi: AccessControl__factory.abi,
        client,
      });

      for (const actor of listAddressToCheck) {
        const [
          isMinterEUR,
          isMinterUSD,
          hasRoleGovernor,
          hasRoleGuardian,
          hasRoleFlashloaner,
          hasRoleProposer,
          hasRoleExecutor,
          hasRoleCanceller,
          hasRoleDefaultAdmin,
        ] = await Promise.all([
          EURA.read.isMinter([actor]),
          USDA.read.isMinter([actor]),
          core.read.hasRole([GOVERNOR_ROLE, actor]),
          core.read.hasRole([GUARDIAN_ROLE, actor]),
          core.read.hasRole([FLASHLOANER_TREASURY_ROLE, actor]),
          timelockContract.read.hasRole([PROPOSER_ROLE, actor]),
          timelockContract.read.hasRole([EXECUTOR_ROLE, actor]),
          timelockContract.read.hasRole([CANCELLER_ROLE, actor]),
          timelockContract.read.hasRole([DEFAULT_ADMIN_ROLE, actor]),
        ]);

        if (isMinterEUR && !_authorizedMinter(chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("EURA - minter role");
          } else {
            actors[actor] = ["EURA - minter role"];
          }
        }
        if (isMinterUSD && !_authorizedMinter(chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("USDA - minter role");
          } else {
            actors[actor] = ["USDA - minter role"];
          }
        }
        if (
          hasRoleGovernor &&
          !_authorizedGovernor(chainId, chainRegistry, actor)
        ) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - governor role");
          } else {
            actors[actor] = ["Timelock - governor role"];
          }
        }
        if (
          hasRoleGuardian &&
          !_authorizedGuardian(chainId, chainRegistry, actor)
        ) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - guardian role");
          } else {
            actors[actor] = ["Timelock - guardian role"];
          }
        }
        if (
          hasRoleFlashloaner &&
          !_authorizedFlashloaner(chainRegistry, actor)
        ) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - flashloaner role");
          } else {
            actors[actor] = ["Timelock - flashloaner role"];
          }
        }
        if (
          hasRoleProposer &&
          !_authorizedProposer(chainId, chainRegistry, actor)
        ) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - proposer role");
          } else {
            actors[actor] = ["Timelock - proposer role"];
          }
        }
        if (hasRoleExecutor && !_authorizedExecutor(chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - executor role");
          } else {
            actors[actor] = ["Timelock - executor role"];
          }
        }
        if (hasRoleCanceller && !_authorizedCanceller(chainRegistry, actor)) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - canceller role");
          } else {
            actors[actor] = ["Timelock - canceller role"];
          }
        }
        if (
          hasRoleDefaultAdmin &&
          !_authorizeDefaultAdmin(chainRegistry, actor)
        ) {
          if (actors.hasOwnProperty(actor)) {
            actors[actor].push("Timelock - default admin role");
          } else {
            actors[actor] = ["Timelock - default admin role"];
          }
        }

        await Promise.all(
          allContracts.map(async (contractToCheck) => {
            const instance = getContract({
              address: contractToCheck,
              abi: AccessControl__factory.abi,
              client,
            });
            return _checkAddressAccessControl(
              chainId,
              chainRegistry,
              instance,
              actor
            );
          })
        );

        if (_isMerklDeployed(chainRegistry)) {
          const coreMerkl = getContract({
            address: chainRegistry.Merkl.CoreMerkl,
            abi: AccessControl__factory.abi,
            client,
          });
          const [hasRoleGovernor, hasRoleGuardian, hasRoleFlashloaner] =
            await Promise.all([
              coreMerkl.read.hasRole([GOVERNOR_ROLE, actor]),
              coreMerkl.read.hasRole([GUARDIAN_ROLE, actor]),
              coreMerkl.read.hasRole([FLASHLOANER_TREASURY_ROLE, actor]),
            ]);

          if (
            hasRoleGovernor &&
            !_authorizedGovernor(chainId, chainRegistry, actor)
          ) {
            if (actors.hasOwnProperty(actor)) {
              actors[actor].push("Merkl Core - governor role");
            } else {
              actors[actor] = ["Merkl Core - governor role"];
            }
          }
          if (
            hasRoleGuardian &&
            !_authorizedGuardian(chainId, chainRegistry, actor)
          ) {
            if (actors.hasOwnProperty(actor)) {
              actors[actor].push("Merkl Core - guardian role");
            } else {
              actors[actor] = ["Merkl Core - guardian role"];
            }
          }
          if (hasRoleFlashloaner) {
            if (actors.hasOwnProperty(actor)) {
              actors[actor].push("Merkl Core - flashloaner role");
            } else {
              actors[actor] = ["Merkl Core - flashloaner role"];
            }
          }
        }

        if (chainId == ChainId.MAINNET) {
          const distributor = getContract({
            address: chainRegistry.AngleDistributor,
            abi: AccessControl__factory.abi,
            client,
          });
          const [hasRoleGovernor, hasRoleGuardian] = await Promise.all([
            distributor.read.hasRole([GOVERNOR_ROLE, actor]),
            distributor.read.hasRole([GUARDIAN_ROLE, actor]),
          ]);

          if (
            hasRoleGovernor &&
            !_authorizedGovernor(chainId, chainRegistry, actor)
          ) {
            if (actors.hasOwnProperty(actor)) {
              actors[actor].push("Angle Distributor - governor role");
            } else {
              actors[actor] = ["Angle Distributor - governor role"];
            }
          }
          if (
            hasRoleGuardian &&
            !_authorizedGuardian(chainId, chainRegistry, actor)
          ) {
            if (actors.hasOwnProperty(actor)) {
              actors[actor].push("Angle Distributor - guardian role");
            } else {
              actors[actor] = ["Angle Distributor - guardian role"];
            }
          }
        }
      }

      const message = await updateMessageWithRolesAndActors(roles, actors, chainId);
      const title = `⛓️ Chain: ${chainId}`;
      embeds.push(new EmbedBuilder().setTitle(title).setDescription(message));
    })
  );
  return embeds
};

async function updateMessageWithRolesAndActors(roles, actors) {
  let messageUpdates = [];

  for (const role of roles) {
    messageUpdates.push(
      `${role}\n`
    );
  };
  for (const actor of Object.keys(actors)) {
    messageUpdates.push(`\n👨‍🎤 **Actor: ${actor}**\n`);
    for (const role of actors[actor]) {
      messageUpdates.push(`${role}\n`);
    }
  };

  const message = messageUpdates.join("");

  return message;
}


const getChannel = (discordClient, channelName) => {
  return discordClient.channels.cache.find(
    (channel) => channel.name === channelName
  );
};

const rolesChannel = "roles-on-chain";

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages],
});

client.on("ready", async () => {
  console.log(`Logged in as ${client.user.tag}!`);

  const chainIds = process.env.CHAIN_IDS.split(",").map((chainId) =>
    parseInt(chainId)
  );

  const channel = getChannel(client, rolesChannel);
  if (!channel) {
    console.log("discord channel not found");
    return;
  }

  const embeds = await checkRoles(chainIds);

  const lastMessages = (
    await channel.messages.fetch({ limit: 20, sort: "timestamp" })
  )
    .map((m) => m.embeds)
    .flat();
  const latestChainIdsMessages = chainIds
    .map((chain) => lastMessages.find((m) => m?.title == `⛓️ Chain: ${chain}`))
    .filter((m) => m);
  for (const embed of embeds) {
    if (
      latestChainIdsMessages.find(
        (m) => {
          const description = m.data.description.split("\n");
          const embedDescription = embed.data.description.split("\n");
          return description.every((line) => embedDescription.includes(line));
        })
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

client.login(process.env.DISCORD_BOT_TOKEN);
