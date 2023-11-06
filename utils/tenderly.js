import axios from 'axios';

const SIMULATE_URL = `https://api.tenderly.co/api/v1/account/${process.env.TENDERLY_USER}/project/${process.env.TENDERLY_PROJECT}/simulate`;
const opts = { headers: { 'X-Access-Key': process.env.TENDERLY_ACCESS_KEY } };

// Ensure an argument has been provided
if (process.argv.length < 7) {
  console.error('Please provide all required inputs.');
  process.exit(1);
}

const chainId = process.argv[2];
const data = process.argv[3];
const from = process.argv[4];
const to = process.argv[5];
const value = process.argv[6];

const body = {
  from: from,
  gas: 8_000_000,
  gas_price: '0',
  input: data,
  network_id: chainId,
  save: true,
  save_if_fails: false,
  simulation_type: 'full',
  to: to,
  value: value,
};

try {
  const resp = await axios.post(SIMULATE_URL, body, opts);

  console.log(`https://dashboard.tenderly.co/public/angle/app/simulator/${resp.data?.simulation?.id}`);
} catch (e) {
  console.log('error', e);
}
