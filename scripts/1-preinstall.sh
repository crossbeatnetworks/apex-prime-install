#!/usr/bin/env bash
set -e -x

source ../install.conf


# #
# ## 1) Basic setup
# #

echo "Doing basic setup..."

# update system and set autoremove and autoclean
sudo apt update -y && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y

# install basic tools
sudo apt-get install screen curl htop -y

if [ -z "$SSH_PORT" ]; then
  echo 'Expected $SSH_PORT variable to be set and not empty. Check install.conf'
  exit 10
fi

if [ -z "$APP_USERNAME" ]; then
  echo 'Expected $APP_USERNAME variable to be set and not empty. Check install.conf'
  exit 10
fi

echo "Application Username [ $APP_USERNAME ] found in config"

if [[ $APP_USERNAME == "root" ]]; then
  echo "Don't get cute with me"
  exit 15
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

  HOMEDIR=$( getent passwd "$APP_USERNAME" | cut -d: -f6 )

  echo "App User home directory [ $HOMEDIR ]"

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
    sudo mkdir -p "$HOMEDIR/.ssh"
    sudo chown $APP_USERNAME:$APP_USERNAME "$HOMEDIR/.ssh"
    cat "${HOME}/.ssh/authorized_keys" | sudo tee -a "$HOMEDIR/.ssh/authorized_keys" > /dev/null
    sudo chown $APP_USERNAME:$APP_USERNAME $HOMEDIR/.ssh/authorized_keys
    sudo chmod 600 $HOMEDIR/.ssh/authorized_keys
    echo "Copied authorized keys to $APP_USERNAME"
  else
    echo "Skipped key copying"
  fi

  SCRIPTSDIR="$HOMEDIR/scripts"

  sudo mkdir -p $SCRIPTSDIR
  sudo chown $APP_USERNAME:$APP_USERNAME $SCRIPTSDIR

  sudo cp ./2-install.sh $SCRIPTSDIR/
  sudo cp ../install.conf $HOMEDIR/
  sudo chown $APP_USERNAME:$APP_USERNAME $SCRIPTSDIR/2-install.sh $HOMEDIR/install.conf

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

# install fail2ban
sudo apt-get install fail2ban python3-systemd -y

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

# check fail2ban service status
sudo systemctl status fail2ban

# recommend verifying that fail2ban is working by making a single login attempt failure
# then observing it in the `fail2ban-client status sshd` output
sudo tail /var/log/fail2ban.log

sudo fail2ban-client status sshd

echo ""
echo "Preinstall Done. Be sure to verify ssh connectivity before exiting out of current session."
echo "Reboot test is also recommended here after ssh functionality is verified."
echo ""

exit 0
