# Guide to test facets update

## Angle-Transmuter repo

First you need to have `selectors_replace.json` and `selectors_add.json` in the script folder. As there is no direct way 
to differentiate between the previous selectors and the one added, you first need to run:
```bash
yarn generate
```

This will populate the `scripts/selector.json` file, you then need to copy paste all selectors that needs to be replace in `scripts/selectors_replace.json`,
which are all except the `updateOracle(address)` one which should be `0x1cb44dfc00000000000000000000000000000000000000000000000000000000`. This one should be 
put `scripts/selector_add.json`.

You are all set to test that new facets are non breaking changes:
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

First you need to copy paste the previous files `selectors_replace.json` and `selectors_add.json` into `./scripts/proposals/transmuter/selectors_replace.json` and `./scripts/proposals/transmuter/selectors_add.json`

Update the address previously logged into `./TransmuterUtils.s.sol` and run:

```bash
yarn create:proposal
```

You will be prompted to specify which proposal you want to submit, enter:

```bash
TransmuterUpdateFacets
```

If will then propose to post the proposal --> Say NO