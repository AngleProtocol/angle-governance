#! /bin/bash

source lib/utils/helpers/common.sh


function chain_to_name {
  chain=$1

  case $chain in
    "0")
      echo "Fork"
      ;;
    "1")
      echo "Mainnet"
      ;;
    "2")
      echo "Arbitrum"
      ;;
    "3")
      echo "Polygon"
      ;;
    "4")
      echo "Gnosis"
      ;;
    "5")
      echo "Avalanche"
      ;;
    "6")
      echo "Base"
      ;;
    "7")
        echo "BinanceSmartChain"
        ;;
    "8")
        echo "Celo"
        ;;
    "9")
        echo "PolygonZkEvm"
        ;;
    "10")
        echo "Optimism"
        ;;
    "11")
        echo "Linea"
        ;;
    *)
      ;;
  esac
}

function usage {
  echo "bash createAngleSideChainMultiBridge.sh <chain> <totalLimit> <hourlyLimit> <chainTotalHourlyLimit> <mock> <?expectedAddress>"
  echo ""
  echo -e "chain: chain to deploy on"
  echo -e "\t0: Fork"
  echo -e "\t1: Ethereum Mainnet"
  echo -e "\t2: Arbitrum"
  echo -e "\t3: Polygon"
  echo -e "\t4: Gnosis"
  echo -e "\t5: Avalanche"
  echo -e "\t6: Base"
  echo -e "\t7: Binance Smart Chain"
  echo -e "\t8: Celo"
  echo -e "\t9: Polygon ZkEvm"
  echo -e "\t10: Optimism"
  echo -e "\t11: Linea"
  echo -e "totalLimit: total limit for the token"
  echo -e "hourlyLimit: hourly limit for the token"
  echo -e "chainTotalHourlyLimit: total hourly limit for the chain"
  echo -e "mock: mock deployment (true/false)"
  echo -e "expectedAddress: expected address for the token (optional)"
  echo ""
}

function main {
    if [[ $# -ne 5 && $# -ne 6 ]]; then
        usage
        exit 1
    fi
    chain=$1
    totalLimit=$2
    hourlyLimit=$3
    chainTotalHourlyLimit=$4
    mock=$5
    expectedAddress=$6

    if [ -z "$chain" ] || [ -z "$totalLimit" ] || [ -z "$hourlyLimit" ] || [ -z "$chainTotalHourlyLimit" ] || [ -z "$mock" ]; then
        echo "Missing arguments"
        exit 1
    fi

    if [ ! -f .env ]; then
        echo ".env not found!"
        exit 1
    fi
    source .env

    chainName=$(chain_to_name $chain)
    chainUri=$(chain_to_uri $chain)
    chainId=$(chain_to_chainId $chain)
    if [[ -z "$chainUri" || -z "$chainName" || -z "$chainId" ]]; then
        echo "Invalid chain"
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
    # check if mock is a boolean
    if [[ "$mock" != "true" && "$mock" != "false" ]]; then
        echo "Mock must be true or false"
        exit 1
    fi

    mainnet_uri=$(chain_to_uri 1)

    if [[ ! -z "$expectedAddress" ]]; then
       export EXPECTED_ADDRESS=$expectedAddress
    fi
    if [[ "$mock" == "true" ]]; then
        export MOCK=true
    fi

    export CHAIN_ID=$chainId
    export CHAIN_NAME=$chainName
    export TOTAL_LIMIT=$totalLimit
    export HOURLY_LIMIT=$hourlyLimit
    export CHAIN_TOTAL_HOURLY_LIMIT=$chainTotalHourlyLimit

    if [[ "$mock" == "true" ]]; then
        echo ""
        echo "Enter the real governor:"
        read governor

        if [ -z "$governor" ]; then
            echo "Missing governor"
            exit 1
        fi

        export REAL_GOVERNOR=$governor
    fi

    echo ""
    echo "Running deployment on chain $chainName with total limit: $totalLimit, hourly limit: $hourlyLimit and chain total hourly limit: $chainTotalHourlyLimit"

    cd lib/angle-tokens && MNEMONIC_MAINNET=$MNEMONIC_MAINNET forge script DeployAngleSideChainMultiBridge --fork-url $chainUri --broadcast --verify && cd ../..

    if [ $? -ne 0 ]; then
        echo ""
        echo "Deployment failed"
        exit 1
    fi

    echo ""
    echo "Deployment successful"

    echo ""
    echo "Would you like to create the proposal for the token side chain multi bridge ? (yes/no)"

    read createProposal

    if [[ $createProposal == "yes" ]]; then

        echo ""
        echo "Enter the description of the proposal:"
        read description

        if [ -z "$description" ]; then
            echo "Missing description"
            exit 1
        fi

        export DESCRIPTION=$description

        FOUNDRY_PROFILE=dev forge script ConnectAngleSideChainMultiBridge --fork-url $mainnet_uri

        if [ $? -ne 0 ]; then
            echo ""
            echo "Proposal creation failed"
            exit 1
        fi

        # TODO run tests

        echo "Proposal created successfully"

        echo ""
        echo "Would you like to execute the proposal ? (yes/no)"
        read execute

        if [[ $execute == "yes" ]]; then
            FOUNDRY_PROFILE=dev forge script Propose --fork-url $mainnet_uri --broadcast
        fi
    fi
}

main $@
