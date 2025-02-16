#!/usr/bin/env bash
set -e

source ./install.conf

if [ -z "$NETWORK" ]; then
  echo 'Expected $NETWORK variable to be set and not empty. Check install.conf'
  exit 11
fi

# #
# ## 3) Node installation
# #

# TODO: Add a check to make sure this script is being run by the application user

echo "Installing Apex Prime node software using guild-operators-apex scripts"

CPU_ARCH=`uname -m`

if [ -z "$CPU_ARCH" ]; then
  echo 'CPU Architecture not able to be identified via uname -m'
  exit 12
fi

echo "CPU Architecture identified as [ $CPU_ARCH ]"

# Clear out guild-operators-apex directory
cd $HOME && rm -rf ./guild-operators-apex

# Clone guild-operators-apex repository
cd $HOME && git clone https://github.com/mlabs-haskell/guild-operators-apex.git

# TODO: add support for x86_64 and branch based on $CPU_ARCH

# run deploy script
cd $HOME && guild-operators-apex/scripts/cnode-helper-scripts/guild-deploy.sh -b main -n $NETWORK -t cnode -s pblfs

. ${HOME}/.bashrc

wget -c https://github.com/armada-alliance/cardano-node-binaries/raw/f756acfc946f158dcac966d006f4b293355802ff/static-binaries/cardano-9_2_1-aarch64-static-musl-ghc_966.tar.zst -O - | tar -I zstd -xv

cp $HOME/cardano-9_2_1-aarch64-static-musl-ghc_966/* $HOME/.local/bin/

# Check the cardano-cli and cardano-node versions
cardano-cli --version

cardano-node --version

# You should see something like this:
#
# cardano-cli 9.4.1.0 - linux-x86_64 - ghc-9.6
# git rev 0000000000000000000000000000000000000000
# cardano-node 9.2.1 - linux-x86_64 - ghc-8.10
# git rev 5d3da8ac771ee5ed424d6c78473c11deabb7a1f3
#
# Make sure cardano-node is 9.2.1

# TODO: Add node tcp port configuration value and update the port in env file

echo "Okay now configure your $CNODE_HOME/files/topology.json and $CNODE_HOME/scripts/env"
echo "Then you can start your node by running the below commands:"
echo ""
echo "sudo systemctl start cnode.service"
echo "sudo systemctl start cnode-submit-api.service"
