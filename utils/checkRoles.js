const { readFileSync } = require('fs');
const { Client, GatewayIntentBits, EmbedBuilder } = require('discord.js');

const getChannel = (discordClient, channelName) => {
  return (discordClient.channels.cache).find((channel) => channel.name === channelName);
};

const rolesChannel = "roles-on-chain"

const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages] });

client.on('ready', async () => {
  console.log(`Logged in as ${client.user.tag}!`);

  const channel = getChannel(client, rolesChannel);
  if (!channel) {
    console.log('discord channel not found');
    return;
  }

  const content = readFileSync('./scripts/roles.json');
  const roles = JSON.parse(content);
  const chains = Object.keys(roles);
  await Promise.all(chains.map(async chain => {
    const title = `⛓️ Chain: ${chain}`;
    const keys = Object.keys(roles[chain]);
    let message = ""
    await Promise.all(keys.map(async key => {
      if (!isNaN(parseInt(key))) {
          message += `\n👨‍🎤 **Actor: ${key}**\n`;
          const actorKeys = Object.keys(roles[chain][key]);
          await Promise.all(actorKeys.map(actorKey => {
              message += `${roles[chain][key][actorKey].toString()}\n`;
          }));
      } else {
          message += `${roles[chain][key]}\n`;
      }
      }));
      const embed = new EmbedBuilder().setTitle(title).setDescription(message);
      await channel.send({ embeds: [embed] });
    }));
    process.exit(0);
});

client.login(process.env.DISCORD_TOKEN);

