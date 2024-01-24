const { registry } = require('@angleprotocol/sdk');
const { ethers } = require('ethers');

// Ensure an argument has been provided
if (process.argv.length < 3) {
  console.error('Please provide a chain input as an argument.');
  process.exit(1);
}

// Get the argument from the command line input
// process.argv[0] is the node command
// process.argv[1] is the path to the runner.js file
// process.argv[2] is the first argument provided by the user
const chainInput = process.argv[2];

// Try to parse the input as a number if possible
if(isNaN(Number(chainInput))) process.exit(1);
const parsedInput = Number(chainInput);

// Function to get all addresses from the registry
function getAllAddresses(registry) {
  let addresses = [];

  for (let key in registry) {
    if (typeof registry[key] === 'object' && registry[key] !== null) {
      // If the value is a nested object, recursively get addresses
      addresses = addresses.concat(getAllAddresses(registry[key]));
    } else {
      // If the value is not an object, assume it's an address and add to the list
      addresses.push(ethers.utils.getAddress(registry[key])?.toString());
    }
  }

  return addresses;
}

// Call the function with the registry
let allAddresses = getAllAddresses(registry(parsedInput));
allAddresses = [...new Set(allAddresses)];
const encodedAddresses = ethers.utils.defaultAbiCoder.encode(['address[]'], [allAddresses]);
console.log(encodedAddresses);