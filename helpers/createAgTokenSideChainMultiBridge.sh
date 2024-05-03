#! /bin/bash

source lib/utils/helpers/common.sh

function usage {
  echo "bash createAgTokenSideChainMultiBridge.sh <chain> <chainUri> <stableName>"
  echo ""
  echo -e "chainId: chain to run the script on"
  echo -e "chainUri: rpc uri for the chain"
  echo -e "stableName: name of the stable token"
  echo ""
}

function main {
    if [[ $# -ne 4 ]]; then
        usage
        exit 1
    fi
    chain=$1
    chainUri=$2
    stableName=$3

    if [ -z "$chain" ] || [ -z "$chainUri" ] || [ -z "$stableName" ]; then
        echo "Missing arguments"
        exit 1
    fi

    if [ ! -f .env ]; then
        echo ".env not found!"
        exit 1
    fi
    source .env

    export CHAIN_ID=$chain
    export STABLE_NAME=$stableName

    echo ""
    echo "Running deployment on chain $chain for stable token $stableName"

    FOUNDRY_PROFILE=dev cd lib/angle-tokens && forge script DeployAgTokenSideChainMultiBridge --rpc-url $chainUri --verify --broadcast && cd ../..

    if [ $? -ne 0 ]; then
        echo ""
        echo "Deployment failed"
        exit 1
    fi

    echo ""
    echo "Deployment successful"

    echo ""
    echo "Would you like to create the proposal for the ag token side chain multi bridge ? (y/n)"

    read createProposal

    if [[ $createProposal == "yes" ]]; then

        echo ""
        echo "Enter the layerZero token address:"
        read layerZeroTokenAddress

        if [ -z "$layerZeroTokenAddress" ]; then
            echo "Missing layerZero token address"
            exit 1
        fi

        echo ""
        echo "Enter the stable token address:"
        read stableTokenAddress

        if [ -z "$stableTokenAddress" ]; then
            echo "Missing stable token address"
            exit 1
        fi

        echo ""
        echo "Enter the chain total hourly limit:"
        read chainTotalHourlyLimit

        if [ -z "$chainTotalHourlyLimit" ]; then
            echo "Missing chain total hourly limit"
            exit 1
        fi

        # Check if chain total hourly limit is greater or equal than 0
        if [ $chainTotalHourlyLimit -lt 0 ]; then
            echo "Chain total hourly limit must be greater or equal than 0"
            exit 1
        fi

        echo ""
        echo "Enter the description:"
        read description

        if [ -z "$description" ]; then
            echo "Missing description"
            exit 1
        fi

        export LZ_TOKEN=$layerZeroTokenAddress
        export DESCRIPTION=$description
        export TOKEN=$stableTokenAddress
        export CHAIN_TOTAL_HOURLY_LIMIT=$chainTotalHourlyLimit

        FOUNDRY_PROFILE=dev forge script ConnectAgTokenSideChainMultiBridge

        if [ $? -ne 0 ]; then
            echo ""
            echo "Proposal creation failed"
            exit 1
        fi

        # TODO run tests

        echo "Proposal created successfully"

        echo ""
        echo "Would you like to create the proposal ? (yes/no)"
        read execute

        if [[ $execute == "yes" ]]; then
            mainnet_uri=$(chain_to_uri 1)
            FOUNDRY_PROFILE=dev forge script scripts/proposals/Propose.s.sol:Propose --fork-url $mainnet_uri --broadcast
        fi
    fi
}

main $@
