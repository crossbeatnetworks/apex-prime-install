#!/usr/bin/env bash
set -e -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/../install.conf

# Copy stdout and stderr to log file
if [[ -n "$LOG_FILE" ]]; then
  sudo touch $LOG_FILE
  exec > >(sudo tee -a "$LOG_FILE") 2>&1
fi

# #
# ## 1) Basic setup
# #

echo "Doing basic setup..."

# update system and set autoremove and autoclean
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get autoremove -y
sudo apt-get autoclean -y

# install basic tools and packages used in preinstall
sudo apt-get install screen curl htop fail2ban python3-systemd -y

if [ -z "$SSH_PORT" ]; then
  echo 'Expected $SSH_PORT variable to be set and not empty. Check install.conf'
  exit 10
fi

if [ -z "$APP_USERNAME" ]; then
  echo 'Expected $APP_USERNAME variable to be set and not empty. Check install.conf'
  exit 11
fi

echo "Application Username [ $APP_USERNAME ] found in config"

if [[ $APP_USERNAME == "root" ]]; then
  echo "Don't get cute with me"
  exit 99
fi

if [[ $USER == $APP_USERNAME ]]; then
  echo "Already running as [ $APP_USERNAME ] .. not creating a user"
else

  if id -u "$APP_USERNAME" &>/dev/null; then
    echo "User [ $APP_USERNAME ] already exists."
  else
    sudo useradd -m -s /bin/bash $APP_USERNAME
    echo "User [ $APP_USERNAME ] created."
  fi

  APP_USER_HOME_DIR=$( getent passwd "$APP_USERNAME" | cut -d: -f6 )

  echo "App User home directory [ $APP_USER_HOME_DIR ]"

  echo "Adding user [ $APP_USERNAME ] to sudo group"

  sudo usermod -aG sudo $APP_USERNAME

  sudo usermod -aG $USER $APP_USERNAME

  echo "Setting sudo password for [ $APP_USERNAME ] user"

  # set password for the new user (needed for sudo)
  sudo passwd $APP_USERNAME

  COPY_AUTHORIZED_KEYS=""
  while [[ -z "$COPY_AUTHORIZED_KEYS" ]]; do
    echo ""
    read -n 1 -p "Copy authorized keys from current user to $APP_USERNAME (y/n)? " ANSWER
    if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
      COPY_AUTHORIZED_KEYS=true
    elif [[ "$ANSWER" =~ ^[Nn]$ ]]; then
      COPY_AUTHORIZED_KEYS=false
    fi
  done

  echo ""

  if [[ "$COPY_AUTHORIZED_KEYS" == true ]]; then
    sudo mkdir -p "$APP_USER_HOME_DIR/.ssh"
    sudo chown $APP_USERNAME:$APP_USERNAME "$APP_USER_HOME_DIR/.ssh"
    cat "${HOME}/.ssh/authorized_keys" | sudo tee -a "$APP_USER_HOME_DIR/.ssh/authorized_keys" > /dev/null
    sudo chown $APP_USERNAME:$APP_USERNAME $APP_USER_HOME_DIR/.ssh/authorized_keys
    sudo chmod 600 $APP_USER_HOME_DIR/.ssh/authorized_keys
    echo "Copied authorized keys to $APP_USERNAME"
  else
    echo "Skipped key copying"
  fi

fi

# test ssh as the new user

# check for existing swap
sudo swapon -s
sudo free -h

if [[ -n $SWAP_FILE && -n $SWAP_SIZE ]]; then

  echo "swap parameters found"

  # Check if swap file exists
  if [ ! -f "$SWAP_FILE" ]; then
    # Create the swap file
    sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE"

    # Set file permissions
    sudo chmod 600 "$SWAP_FILE"

    # Add swap entry to /etc/fstab
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab

    # Activate swap
    sudo swapon "$SWAP_FILE"
    echo "Swap file created and activated successfully!"
  else
    echo "Swap file already exists: $SWAP_FILE"
    echo "Leaving swap file and swap configuration as is"
  fi

else

  echo "Swap config parameter(s) empty, skipping swap creation"

fi

echo "Basic system setup done."

# #
# ## 2) Server Hardening
# #

echo "Hardening server.."

echo "Updating sshd config"

sudo tee /etc/ssh/sshd_config.d/70-node-hardening.conf << CONFIGBLOCK

PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
Port $SSH_PORT

CONFIGBLOCK

# Check updated config validity. If no output then it is good
sudo sshd -t

# Check whether sshd is using an ssh.socket
if [[ -n `sudo systemctl status ssh | grep 'TriggeredBy:.*ssh\.socket'` ]]; then
  echo "sshd socket detected, updating port in ssh.socket file"
  sudo sed -i -e s/^ListenStream=22$/ListenStream=$SSH_PORT/ /etc/systemd/system/ssh.service.requires/ssh.socket
  # daemon reload
  sudo systemctl daemon-reload
fi

# Restart sshd service
sudo systemctl restart ssh

# HIGHLY RECOMMEND adding entries in local machine ssh config (in ~/.ssh/config)
# Host af-main-relay-1
#   User apex
#   IdentityFile ~/.ssh/yourprivatekey.pem
#   HostName ip.address.of.relay
#   Port 2822

# Disable root direct user access

sudo tee /etc/fail2ban/jail.d/local.conf << CONFIGBLOCK

[sshd]
backend = systemd
enabled = true
port = $SSH_PORT
filter = sshd[mode=aggressive]
maxretry = 5
# whitelisted IP addresses
# ignoreip = <list of whitelisted IP address, your local daily laptop/pc>

CONFIGBLOCK

# restart fail2ban service
sudo systemctl restart fail2ban

# wait a couple seconds for fail2ban to start up
sleep 2

# check fail2ban service status
sudo systemctl status fail2ban

# recommend verifying that fail2ban is working by making a single login attempt failure
# then observing it in the `fail2ban-client status sshd` output
sudo tail /var/log/fail2ban.log

sudo fail2ban-client status sshd

# Copy scripts to app user home directory if app user is not current user
if [[ $USER != $APP_USERNAME ]]; then

  APP_USER_SCRIPTS_DIR="$APP_USER_HOME_DIR/scripts"

  sudo mkdir -p $APP_USER_SCRIPTS_DIR
  sudo chown $APP_USERNAME:$APP_USERNAME $APP_USER_SCRIPTS_DIR

  sudo cp $SCRIPT_DIR/2-install.sh $APP_USER_SCRIPTS_DIR/
  sudo cp $SCRIPT_DIR/../install.conf $APP_USER_HOME_DIR/
  sudo chown $APP_USERNAME:$APP_USERNAME $APP_USER_SCRIPTS_DIR/2-install.sh $APP_USER_HOME_DIR/install.conf

fi

# Disable writing commands to output, only thing remaining are echo statements
# and no need to double those
set +x

echo -e "\nPreinstall Done. Be sure to verify ssh connectivity before exiting out of current session."
echo -e "Reboot test is also recommended here (BUT ONLY AFTER ssh functionality is verified).\n"

echo " *** IMPORTANT *** : Make sure your firewall allows incoming TCP connections on port $SSH_PORT"

if [[ $USER != $APP_USERNAME ]]; then
  echo " *** IMPORTANT *** : Make sure you can initiate a new ssh connection to this server and execute sudo as [ $APP_USERNAME ]"
else
  echo " *** IMPORTANT *** : Make sure you can initiate a new ssh connection to this server"
fi

echo -e " *** IMPORTANT *** : BEFORE disconnecting your current session\n"

echo "Once this is confirmed, the next step is to run the 2-install.sh script as $APP_USERNAME"

exit 0
