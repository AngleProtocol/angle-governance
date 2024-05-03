#! /bin/bash

source lib/utils/helpers/common.sh

function usage {
  echo "bash createTokenSideChainMultiBridge.sh <chain> <chainUri> <chainName> <totalLimit> <hourlyLimit> <chainTotalHourlyLimit>"
  echo ""
  echo -e "chainId: chain to run the script on"
  echo -e "chainUri: rpc uri for the chain"
  echo -e "chainName: name of the chain"
  echo -e "totalLimit: total limit for the token"
  echo -e "hourlyLimit: hourly limit for the token"
  echo -e "chainTotalHourlyLimit: total hourly limit for the chain"
  echo ""
}

function main {
    if [[ $# -ne 6 ]]; then
        usage
        exit 1
    fi
    chain=$1
    chainUri=$2
    chainName=$3
    totalLimit=$4
    hourlyLimit=$5
    chainTotalHourlyLimit=$6

    if [ -z "$chain" ] || [ -z "$chainUri" ] || [ -z "$chainName" ] || [ -z "$totalLimit" ] || [ -z "$hourlyLimit" ] || [ -z "$chainTotalHourlyLimit" ]; then
        echo "Missing arguments"
        exit 1
    fi
    # Check if chain is a positive integer
    if ! [[ $chain =~ ^[0-9]+$ ]]; then
        echo "Chain must be a positive integer"
        exit 1
    fi
    # Check if totalLimit is a positive or null integer
    if ! [[ $totalLimit =~ ^[0-9]+$ ]]; then
        echo "Total limit must be a positive integer"
        exit 1
    fi
    # Check if hourlyLimit is a positive or null integer
    if ! [[ $hourlyLimit =~ ^[0-9]+$ ]]; then
        echo "Hourly limit must be a positive integer"
        exit 1
    fi
    # Check if chainTotalHourlyLimit is a positive or null integer
    if ! [[ $chainTotalHourlyLimit =~ ^[0-9]+$ ]]; then
        echo "Chain total hourly limit must be a positive integer"
        exit 1
    fi

    if [ ! -f .env ]; then
        echo ".env not found!"
        exit 1
    fi
    source .env

    mainnet_uri=$(chain_to_uri 1)

    export CHAIN_ID=$chain
    export CHAIN_NAME=$chainName
    export TOTAL_LIMIT=$totalLimit
    export HOURLY_LIMIT=$hourlyLimit
    export CHAIN_TOTAL_HOURLY_LIMIT=$chainTotalHourlyLimit

    echo ""
    echo "Running deployment on chain $chainName with total limit: $totalLimit, hourly limit: $hourlyLimit and chain total hourly limit: $chainTotalHourlyLimit"

    FOUNDRY_PROFILE=dev cd lib/angle-tokens && forge script DeployTokenSideChainMultiBridge --rpc-url $chainUri --verify --broadcast && cd ../..

    if [ $? -ne 0 ]; then
        echo ""
        echo "Deployment failed"
        exit 1
    fi

    echo ""
    echo "Deployment successful"

    echo ""
    echo "Would you like to create the proposal for the token side chain multi bridge ? (y/n)"

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
        echo "Enter the description:"
        read description

        if [ -z "$description" ]; then
            echo "Missing description"
            exit 1
        fi

        export LZ_TOKEN=$layerZeroTokenAddress
        export DESCRIPTION=$description

        FOUNDRY_PROFILE=dev forge script ConnectTokenSideChainMultiBridge

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
