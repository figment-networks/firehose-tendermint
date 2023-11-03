#!/usr/bin/env bash

set -o errexit
set -o pipefail

CLEANUP=${CLEANUP:-"0"}
NETWORK=${NETWORK:-"mainnet"}
OS_PLATFORM=$(uname -s)
OS_ARCH=$(uname -m)
GAIA_PLATFORM=${GAIA_PLATFORM:-"linux_amd64"}

case $NETWORK in
  mainnet)
    echo "Using MAINNET"
    GAIA_VERSION=${GAIA_VERSION:-"v4.2.1"}
    GAIA_GENESIS="https://raw.githubusercontent.com/cosmos/mainnet/master/genesis/genesis.cosmoshub-4.json.gz"
    GAIA_GENESIS_HEIGHT=${GAIA_GENESIS_HEIGHT:-"5200791"}
    GAIA_ADDRESS_BOOK="https://quicksync.io/addrbook.cosmos.json"
  ;;
  testnet)
    echo "Using TESTNET"
    GAIA_VERSION=${GAIA_VERSION:-"v6.0.0"}
    GAIA_GENESIS="https://raw.githubusercontent.com/cosmos/testnets/master/v7-theta/public-testnet/genesis.json.gz"
    GAIA_GENESIS_HEIGHT=${GAIA_GENESIS_HEIGHT:-"9034670"}
  ;;
  *)
    echo "Invalid network: $NETWORK"; exit 1;
  ;;
esac

case $OS_PLATFORM-$OS_ARCH in
  Darwin-x86_64) GAIA_PLATFORM="darwin_amd64" ;;
  Darwin-arm64)  GAIA_PLATFORM="darwin_arm64" ;;
  Linux-x86_64)  GAIA_PLATFORM="linux_amd64"  ;;
  *) echo "Invalid platform"; exit 1 ;;
esac

if [[ -z $(which "wget" || true) ]]; then
  echo "ERROR: wget is not installed"
  exit 1
fi

if [[ $CLEANUP -eq "1" ]]; then
  echo "Deleting all local data"
  rm -rf ./tmp/ > /dev/null
fi

echo "Setting up working directory"
mkdir -p tmp
pushd tmp

echo "Your platform is $OS_PLATFORM/$OS_ARCH"

if [ ! -f "gaiad" ]; then
  echo "Downloading gaiad $GAIA_VERSION binary"
  wget --quiet -O ./gaiad "https://github.com/graphprotocol/gaia-dm/releases/download/$GAIA_VERSION/gaiad_${GAIA_VERSION}_firehose_$GAIA_PLATFORM"
  chmod +x ./gaiad
fi

if [ ! -d "gaia_home" ]; then
  echo "Configuring home directory"
  ./gaiad --home=gaia_home init $(hostname) 2> /dev/null
  rm -f \
    gaia_home/config/genesis.json \
    gaia_home/config/addrbook.json
fi

if [ ! -f "gaia_home/config/genesis.json" ]; then
  echo "Downloading genesis file"
  wget -O gaia_home/config/genesis.json.gz $GAIA_GENESIS
  gunzip gaia_home/config/genesis.json.gz
fi

case $NETWORK in
  mainnet) # Using addrbook will ensure fast block sync time
    if [ ! -f "gaia_home/config/addrbook.json" ]; then
      echo "Downloading address book"
      wget --quiet -O gaia_home/config/addrbook.json $GAIA_ADDRESS_BOOK
    fi
  ;;
  testnet) # There's no address book for the testnet, use seeds instead
    echo "Configuring p2p seeds"
    sed -i -e 's/seeds = ""/seeds = "639d50339d7045436c756a042906b9a69970913f@seed-01.theta-testnet.polypore.xyz:26656,3e506472683ceb7ed75c1578d092c79785c27857@seed-02.theta-testnet.polypore.xyz:26656"/g' gaia_home/config/config.toml
  ;;
esac

cat << END >> gaia_home/config/config.toml

#######################################################
###       Extractor Configuration Options     ###
#######################################################
[extractor]
enabled = true
output_file = "stdout"
END

if [ ! -f "firehose.yml" ]; then
  cat << END >> firehose.yml
start:
  args:
    - reader
    - merger
    - firehose
  flags:
    common-first-streamable-block: $GAIA_GENESIS_HEIGHT
    common-live-blocks-addr:
    reader-mode: node
    reader-node-path: ./gaiad
    reader-node-args: start --x-crisis-skip-assert-invariants --home=./gaia_home
    reader-node-logs-filter: "module=(p2p|pex|consensus|x/bank)"
    relayer-max-source-latency: 99999h
    verbose: 1
END
fi
