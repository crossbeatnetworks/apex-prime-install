#!/usr/bin/env -S bash -i
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/../install.conf

# Make sure user running this script is the designated app user
if [[ "$USER" != "$APP_USERNAME" ]]; then
  echo "Please run the install script as $APP_USERNAME user"
  exit 80
fi

# Make sure required config options are set
if [[ -z "$NETWORK" ]]; then
  echo 'Expected $NETWORK variable to be set and not empty. Check install.conf'
  exit 11
fi

if [[ -z "$NODE_PORT" ]]; then
  echo 'Expected $NODE_PORT variable to be set and not empty. Check install.conf'
  exit 12
fi

# Copy stdout and stderr to log file
if [[ -n "$LOG_FILE" ]]; then
  sudo touch $LOG_FILE
  exec > >(sudo tee -a "$LOG_FILE") 2>&1
fi

echo -n "Starting install at: "
echo `date "+%Y-%m-%d %H:%M:%S"`

# #
# ## 3) Node installation
# #

echo "Installing node software using guild-operators-apex scripts"

set -x

CPU_ARCH=`uname -m`

if [[ -z "$CPU_ARCH" ]]; then
  echo 'CPU Architecture not able to be identified via uname -m'
  exit 12
fi

echo "CPU Architecture identified as [ $CPU_ARCH ]"

cd $HOME

# Clear out guild-operators-apex directory if it exists
rm -rf ./guild-operators-apex

# Clone guild-operators-apex repository
git clone https://github.com/mlabs-haskell/guild-operators-apex.git

if [[ "$CPU_ARCH" == "aarch64" ]]; then

  # run deploy script
  guild-operators-apex/scripts/cnode-helper-scripts/guild-deploy.sh -b main -n $NETWORK -t cnode -s pl

  wget -nv -c https://github.com/armada-alliance/cardano-node-binaries/raw/f756acfc946f158dcac966d006f4b293355802ff/static-binaries/cardano-9_2_1-aarch64-static-musl-ghc_966.tar.zst -O - | tar -I zstd -xv

  cp $HOME/cardano-9_2_1-aarch64-static-musl-ghc_966/* $HOME/.local/bin/

elif [[ "$CPU_ARCH" == "x86_64" ]]; then

  # run deploy script
  guild-operators-apex/scripts/cnode-helper-scripts/guild-deploy.sh -b main -n $NETWORK -t cnode -s pdlcowx

else

  echo "Unrecognized or unsupported CPU architecture [ $CPU_ARCH ]"
  exit 91

fi

source "$HOME/.bashrc"

# Update node port in env file
sed -i -e "s/^#CNODE_PORT=6000/CNODE_PORT=$NODE_PORT/" "$CNODE_HOME/scripts/env"

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

# Deploy the services
cd "$CNODE_HOME/scripts"

./cnode.sh -d

./submitapi.sh -d

# Stop echoing commands in output
set +x

echo -n "Finished install at: "
echo `date "+%Y-%m-%d %H:%M:%S"`

echo -e "\n *** IMPORTANT *** Make sure your firewall is configured to allow incoming TCP connections on port [ $NODE_PORT ]\n"
echo -e "Now configure your $CNODE_HOME/files/topology.json and $CNODE_HOME/scripts/env"
echo -e "Then you can start your node by running the below commands:\n"
echo -e "  sudo systemctl start cnode.service"
echo -e "  sudo systemctl start cnode-submit-api.service\n"
echo -e "Once cnode.service is running, you can check status by running the below commands:\n"
echo -e "  sudo systemctl status cnode.service"
echo -e "  sudo systemctl status cnode-submit-api.service\n"
echo -e "You can monitor node sync status and network status with the below command:\n"
echo -e "  cd \$CNODE_HOME && scripts/gLiveView.sh"
