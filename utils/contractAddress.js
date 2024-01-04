const { registry } = require('@angleprotocol/sdk');
const { ethers } = require('ethers');

// Ensure an argument has been provided
if (process.argv.length < 4) {
  console.error('Please provide a chain input as an argument.');
  process.exit(1);
}

// Get the argument from the command line input
// process.argv[0] is the node command
// process.argv[1] is the path to the runner.js file
// process.argv[2] is the first argument provided by the user
const chainInput = process.argv[2];
const contracTtype = String(process.argv[3]);

// Try to parse the input as a number if possible
if(isNaN(Number(chainInput))) process.exit(1);
const parsedInput = Number(chainInput);

let contract

if(contracTtype == "governor") contract =  registry(parsedInput)?.AngleGovernor;
else if(contracTtype == "proposalReceiver")  contract = registry(parsedInput)?.ProposalReceiver;
else if(contracTtype == "timelock") contract = registry(parsedInput)?.Timelock;
else if(contracTtype == "proposalSender") contract = registry(parsedInput)?.ProposalSender;

if(!contract) process.exit(1);
// Call the function with the input
const result = ethers.utils.getAddress(contract)?.toString()?.slice(2);
console.log(result);

// let result;
// if(contracTtype == "governor") result = ethers.utils.getAddress(registry(parsedInput).AngleGovernor).toString().slice(2);
// else if(contracTtype == "proposalReceiver") result = ethers.utils.getAddress(registry(parsedInput).ProposalReceiver).toString().slice(2);
// else if(contracTtype == "timelock") result = ethers.utils.getAddress(registry(parsedInput).Timelock).toString().slice(2);
// else if(contracTtype == "proposalSender") result = ethers.utils.getAddress(registry(parsedInput).ProposalSender).toString().slice(2);
// else {
//   console.error('Please provide a correct contract type as an argument.');
//   process.exit(1);
// }
// console.log(result);