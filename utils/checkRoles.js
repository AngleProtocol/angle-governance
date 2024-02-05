const { readFileSync } = require('fs');
const { Client, GatewayIntentBits } = require('discord.js');

const getChannel = (discordClient, channelName) => {
  return (discordClient.channels.cache).find((channel) => channel.name === channelName);
};

const rolesChannel = "roles-on-chain"

const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages] });

client.on('ready', () => {
  console.log(`Logged in as ${client.user.tag}!`);

  const channel = getChannel(client, rolesChannel);
  if (!channel) {
    console.log('discord channel not found');
    return;
  }

  const content = readFileSync('./scripts/roles.json');
  const roles = JSON.parse(content);
  const chains = Object.keys(roles);
  let first = true;
  let message = "";
  chains.forEach(chain => {
    if (first) {
        first = false;
    } else {
        message += '\n';
    }
    message += `======== Chain: ${chain}  =========\n`;
    const keys = Object.keys(roles[chain]);
    keys.forEach(key => {
      if (!isNaN(parseInt(key))) {
          message += `\n======== Actor: ${key}  =========\n`;
          const actorKeys = Object.keys(roles[chain][key]);
          actorKeys.forEach(actorKey => {
              message += `${roles[chain][key][actorKey].toString()}\n`;
          });
      } else {
          message += `${roles[chain][key]}\n`;
      }
      });
    });

    channel.send(message).then(() => {
        console.log('roles sent');
        process.exit(0);
    }).catch((error) => {
        console.log('error sending roles', error);
        process.exit(1);
    });
});

client.login(process.env.DISCORD_TOKEN);

