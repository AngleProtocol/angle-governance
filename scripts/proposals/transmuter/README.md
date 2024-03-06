# Guide to test facets update

## Angle-Tranmuter repo

To test that new facets are non breaking changes run:
```bash
yarn test --match-contract UpdateTransmuterFacets
```

If all tests are passing you can move on to deployment.

You first need to make fork Ethereum:

```bash
yarn fork
```

and then when prompted choose Ethereum.

Open a new terminal and deploy the new facets with:

```bash
yarn deploy:fork UpdateTransmuterFacets
```

Get the addresses for the deployed contracts, you will get a log of this format:

```bash
  Getters deployed at:  0x0....
  Redeemer deployed at:  0x0....
  SettersGovernor deployed at:  0x0....
  Swapper deployed at:  0x0....
  Oracle deployed at:  0x0....
```

## Angle-Governance repo

Update the address previously logged into `./TransmuterUtils.s.sol` and run:

```bash
yarn create:proposal
```

You will be prompted to specify which proposal you want to submit, enter:

```bash
TransmuterUpdateFacets
```

If will then propose to post the proposal --> Say NO