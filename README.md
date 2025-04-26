# apex-prime-install

## Objective
Provide scripts to help streamline Apex Fusion Prime relay node installation and hardening

## Indications
These scripts perform changes to server configurations that can make the server inaccessible or disable the server. The scripts are intended to be used on a newly provisioned machine. If you have invested a significant amount of time preparing or developing your machine, consider not using these scripts as you could potentially lose the work you have put in.

It is recommended that you read through each script carefully and understand what each script will do before you execute any of them.

## Pre-requesites
These scripts are designed to be run on a freshly installed Debian or Ubuntu machine. Git is required.

## Usage

1. Clone the repository
```
git clone https://github.com/crossbeatnetworks/apex-prime-install.git
```

2. Copy configuration file
```
cd apex-prime-install
cp install.conf.example install.conf
```

3. Edit the copied configuration file to your preferences
```
# Use the editor of your choice. I don't know much but I know better than to suggest an editor
```

4. Run the pre-install script
```
./scripts/1-preinstall.sh
```

5. Follow the instructions displayed at the end of the pre-install script output

6. Run the install script as the application user
```
./scripts/2-install.sh
```

## References
These scripts are only possible through the work of many people, some of whom are listed here below.  
The overall procedure is largely based on the tutorial provided by Kash Pool at https://apexkash.com/  
The server hardening portion is based on some of the tutorial steps at https://www.coincashew.com/  
The node binary installation is done by a fork of the Guild Operators scripts at https://github.com/mlabs-haskell/guild-operators-apex  
arm64 node binaries are provided by Armada Allaince at https://github.com/armada-alliance/cardano-node-binaries  
The adaptation of the Guild Operators scripts in order to run on Apex Fusion Prime network are at https://github.com/Scitz0/guild-operators-apex  
Guild Operators documentation can be found at https://cardano-community.github.io/guild-operators/
Apex Fusion documentation can be found at https://developers.apexfusion.org/documentation
