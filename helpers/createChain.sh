#! /bin/bash

source lib/utils/helpers/common.sh

function usage {
  echo "bash createChain.sh <chain> <chainUri>"
  echo ""
  echo -e "chainId: chain to run the script on"
  echo -e "chainUri: rpc uri for the chain"
  echo ""
}

function main {
    if [[ $# -ne 3 ]]; then
        usage
        exit 1
    fi
    chain=$1
    chainUri=$2

    if [ -z "$chain" ] || [ -z "$chainUri" ]; then
        echo "Missing arguments"
        exit 1
    fi

    if [ ! -f .env ]; then
        echo ".env not found!"
        exit 1
    fi
    source .env

    export CHAIN_ID=$chain

    echo ""
    echo "Running deployment on chain $chain"

    FOUNDRY_PROFILE=dev cd lib/angle-tokens && forge script DeployChain --rpc-url $chainUri --verify --broadcast && cd ../..

    if [ $? -ne 0 ]; then
        echo ""
        echo "Deployment failed"
        exit 1
    fi

    echo ""
    echo "Deployment successful"
}

main $@
