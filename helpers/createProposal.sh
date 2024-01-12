#! /bin/bash

function chain_to_uri {
  chain=$1

  case $chain in
    "1")
      echo $ETH_NODE_URI_MAINNET
      ;;
    "2")
      echo $ETH_NODE_URI_ARBITRUM
      ;;
    "3")
      echo $ETH_NODE_URI_POLYGON
      ;;
    "4")
      echo $ETH_NODE_URI_GNOSIS
      ;;
    "5")
      echo $ETH_NODE_URI_AVALANCHE
      ;;
    "6")
      echo $ETH_NODE_URI_BASE
      ;;
    "7")
        echo $ETH_NODE_URI_BSC
        ;;
    "8")
        echo $ETH_NODE_URI_CELO
        ;;
    "9")
        echo $ETH_NODE_URI_POLYGON_ZKEVM
        ;;
    "10")
        echo $ETH_NODE_URI_OPTIMISM
        ;;
    "11")
        echo $ETH_NODE_URI_LINEA
        ;;
    *)
      ;;
  esac
}

function chain_to_chainId {
  chain=$1

  case $chain in
    "1")
      echo "1"
      ;;
    "2")
      echo "42161"
      ;;
    "3")
      echo "137"
      ;;
    "4")
      echo "100"
      ;;
    "5")
      echo "43114"
      ;;
    "6")
      echo "8453"
      ;;
    "7")
        echo "56"
        ;;
    "8")
        echo "42220"
        ;;
    "9")
        echo "1101"
        ;;
    "10")
        echo "10"
        ;;
    "11")
        echo "59144"
        ;;
    *)
      ;;
  esac
}

function usage {
  echo "bash createTx.sh <script> <chain>"
  echo ""
  echo -e "script: path to the script to run"
  echo -e "chain: chain(s) to run the script on (separate with commas)"
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
  echo ""
}

function main {
    command=false
    if [[ $# -ne 2 && $# -ne 0 ]]; then
        usage
        exit 1
    fi
    if [ $# -eq 2 ]; then
        script=$1
        chains=$2
        command=true
    fi

    if [ ! -f .env ]; then
        echo ".env not found!"
        exit 1
    fi
    source .env

    if [ $command != true ]; then
        echo ""
        echo "What script would you like to run ?"

        read script

        if [ -z "$script" ]; then
            echo "No script provided"
            exit 1
        fi

        echo ""

        echo "Which chain(s) would you like to run the script on ? (separate with commas)"
        echo "- 1: Ethereum Mainnet"
        echo "- 2: Arbitrum"
        echo "- 3: Polygon"
        echo "- 4: Gnosis"
        echo "- 5: Avalanche"
        echo "- 6: Base"
        echo "- 7: Binance Smart Chain"
        echo "- 8: Celo"
        echo "- 9: Polygon ZkEvm"
        echo "- 10: Optimism"
        echo "- 11: Linea"

        read chains

        if [ -z "$chains" ]; then
            echo "No chain provided"
            exit 1
        fi
    fi

    mainnet_uri=$(chain_to_uri 1)

    chainIds=""
    for chain in $(echo $chains | sed "s/,/ /g")
    do
        if [[ -z $chainIds ]]; then
            chainIds="$(chain_to_chainId $chain)"
        else
            chainIds="$chainIds,$(chain_to_chainId $chain)"
        fi
    done

    echo ""
    echo "Running on chains $chainIds"

    export CHAIN_IDS=$chainIds
    forge script $script

    if [ $? -ne 0 ]; then
        echo ""
        echo "Script failed"
    fi

    testPath=$(echo $script | sed 's|scripts|test|g' | sed 's|.s.sol|.t.sol|g')
    if [ -f $testPath ]; then
        echo ""
        echo "Running test"
        forge test --match-path $testPath -vvv
    fi

    echo ""
    echo "Would you like to create the proposal ? (yes/no)"
    read execute

    if [[ $execute == "yes" ]]; then
        forge script scripts/interaction/Propose.s.sol:Propose --fork-url $mainnet_uri --broadcast
    fi
}

main $@
