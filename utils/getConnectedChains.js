const { registry, ChainId } = require('@angleprotocol/sdk');
const { ethers } = require('ethers');

if (process.argv.length < 3) {
    console.log('Usage: node getConnectedChains.js <chainId>');
    process.exit(1);
}

const contract = process.argv[2];

// Try to parse the input as a number if possible
let contracts = [];
let chains = [];

for (const chain in ChainId) {
    switch (contract) {
        case 'EURA':
            if (registry(chain)?.EUR?.agToken) {
                contracts.push(registry(chain).EUR.agToken);
                chains.push(chain);
            }
            break;
        case 'USDA':
            if (registry(chain)?.USD?.agToken) {
                contracts.push(registry(chain).USD.agToken);
                chains.push(chain);
            }
            break;
        case 'ANGLE':
            if (registry(chain)?.ANGLE) {
                contracts.push(registry(chain).ANGLE);
                chains.push(chain);
            }
            break;
    }
}

console.log(JSON.stringify({contracts, chains}));