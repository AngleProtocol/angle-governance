#! /bin/bash

source lib/utils/helpers/common.sh

function usage {
  echo "bash createChain.sh <chain> <?governor> <?guardian>"
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
  echo -e "governor: address of the governor (optional)"
  echo -e "guardian: address of the guardian (optional)"
  echo ""
}

function main {
    if [ $# -ne 3 ] && [ $# -ne 5 ]; then
        usage
        exit 1
    fi
    chain=$1
    governor=$2
    guardian=$3

    if [ -z "$chain" ]; then
        echo "Missing arguments"
        exit 1
    fi

    if [ ! -f .env ]; then
        echo ".env not found!"
        exit 1
    fi
    source .env

    chainUri=$(chain_to_uri $chain)
    chainId=$(chain_to_chainId $chain)
    if [ -z "$chainUri" ] || [ -z "$chainId" ]; then
        echo "Invalid chain"
        exit 1
    fi

    export CHAIN_ID=$chain
    if [ ! -z "$governor" ]; then
        export GOVERNOR=$governor
    fi
    if [ ! -z "$guardian" ]; then
        export GUARDIAN=$guardian
    fi

    echo ""
    echo "Running deployment on chain $chain"

    cd lib/angle-tokens && MNEMONIC_MAINNET=$MNEMONIC_MAINNET forge script DeployChain --fork-url $chainUri --verify --broadcast && cd ../..

    if [ $? -ne 0 ]; then
        echo ""
        echo "Deployment failed"
        exit 1
    fi

    echo ""
    echo "Deployment successful"
}

main $@
