const { readFileSync } = require("fs");
const { Client, GatewayIntentBits, EmbedBuilder } = require("discord.js");

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
          if (!isNaN(parseInt(key))) {
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
  const latestChainIdsMessages = chains.map((chain) =>
    lastMessages.find((m) => m?.title == `⛓️ Chain: ${chain}`)
  );
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
