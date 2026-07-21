#!/bin/bash

# Linux Automation - COMP2137 Assignment 2
# By Lucas Shering
# Due Date 7/22/26
# This script checks the current state of server1, makes necessary changes, and reports results

# Check for root privilege

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

echo "Root privilege check passed."

# Networking Section

echo
echo "========================================"
echo " Configuring network"
echo "========================================"

netplanFile="/etc/netplan/10-lxc.yaml"
newAddress="192.168.16.21/24"

if [ ! -f "$netplanFile" ]; then
    echo "ERROR: Netplan file $netplanFile was not found."
    exit 1
fi

if grep -q "$newAddress" "$netplanFile"; then
    echo "Network address is already configured as $newAddress."
else
    echo "Changing the eth1 address to $newAddress."

    sed -i '/^[[:space:]]*eth1:/,/^[[:space:]]*routes:/ {
        s|addresses: \[[^]]*\]|addresses: ['"$newAddress"']|
    }' "$netplanFile"

    if grep -q "$newAddress" "$netplanFile"; then
        echo "Netplan configuration was updated successfully."
    else
        echo "ERROR: Failed to update the Netplan configuration."
        exit 1
    fi
fi

echo "Validating Netplan configuration."

if ! netplan generate; then
    echo "ERROR: Netplan configuration is invalid."
    exit 1
fi

if ip -4 address show dev eth1 | grep -q '192\.168\.16\.21/24'; then
    echo "The live eth1 address is already configured correctly."
else
    echo "Applying Netplan configuration."

    if ! netplan apply; then
        echo "ERROR: Failed to apply Netplan configuration."
        exit 1
    fi

    echo "Netplan configuration applied successfully."
fi

# Hosts file section

echo
echo "========================================"
echo " Configuring /etc/hosts"
echo "========================================"

hostsFile="/etc/hosts"
desiredHostsEntry="192.168.16.21 server1"

if grep -Eq '^192\.168\.16\.21[[:space:]]+server1([[:space:]]|$)' "$hostsFile"; then
    echo "/etc/hosts already contains the correct server1 entry."
else
    echo "Removing old server1 address entries."

    sed -i '/^[0-9][0-9.]*[[:space:]]\+server1\([[:space:]]\|$\)/d' "$hostsFile"

    echo "$desiredHostsEntry" >> "$hostsFile"

    if grep -Eq '^192\.168\.16\.21[[:space:]]+server1([[:space:]]|$)' "$hostsFile"; then
        echo "Added the correct server1 entry to /etc/hosts."
    else
        echo "ERROR: Failed to update /etc/hosts."
        exit 1
    fi
fi

# Software section

echo
echo "========================================"
echo " Installing required software"
echo "========================================"

echo "Updating package lists."

if ! apt-get update; then
    echo "ERROR: Failed to update package lists."
    exit 1
fi

requiredPackages="apache2 squid"

for package in $requiredPackages; do
    if dpkg -s "$package" >/dev/null 2>&1; then
        echo "$package is already installed."
    else
        echo "Installing $package."

        if apt-get install -y "$package"; then
            echo "$package was installed successfully."
        else
            echo "ERROR: Failed to install $package."
            exit 1
        fi
    fi
done

# Service section

echo
echo "========================================"
echo " Checking required services"
echo "========================================"

requiredServices="apache2 squid"

for service in $requiredServices; do
    if systemctl is-active --quiet "$service"; then
        echo "$service is already running."
    else
        echo "Starting $service."

        if systemctl start "$service"; then
            echo "$service started successfully."
        else
            echo "ERROR: Failed to start $service."
            exit 1
        fi
    fi
done

# User account section

echo
echo "========================================"
echo " Configuring user accounts"
echo "========================================"

users="dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda"

for user in $users; do
    if id "$user" >/dev/null 2>&1; then
        echo "$user already exists."
    else
        echo "Creating user $user."

        if ! useradd -m -s /bin/bash "$user"; then
            echo "ERROR: Failed to create user $user."
            exit 1
        fi

        echo "$user was created successfully."
    fi

    if [ "$(getent passwd "$user" | cut -d: -f6)" != "/home/$user" ]; then
        echo "Setting home directory for $user."

        if ! usermod -d "/home/$user" -m "$user"; then
            echo "ERROR: Failed to configure the home directory for $user."
            exit 1
        fi
    else
        echo "$user has the correct home directory."
    fi

    if [ "$(getent passwd "$user" | cut -d: -f7)" != "/bin/bash" ]; then
        echo "Setting Bash as the default shell for $user."

        if ! usermod -s /bin/bash "$user"; then
            echo "ERROR: Failed to configure the shell for $user."
            exit 1
        fi
    else
        echo "$user has Bash as the default shell."
    fi
done

# Special dennis configuration

echo
echo "Configuring sudo access for dennis."

if id -nG dennis | grep -qw sudo; then
    echo "dennis is already a member of the sudo group."
else
    if ! usermod -aG sudo dennis; then
        echo "ERROR: Failed to add dennis to the sudo group."
        exit 1
    fi

    echo "dennis was added to the sudo group."
fi

# SSH key section

echo
echo "========================================"
echo " Configuring SSH keys"
echo "========================================"

for user in $users; do
    homeDir="/home/$user"
    sshDir="$homeDir/.ssh"
    authorizedKeys="$sshDir/authorized_keys"

    echo
    echo "Configuring SSH keys for $user."

    if ! mkdir -p "$sshDir"; then
        echo "ERROR: Failed to create $sshDir."
        exit 1
    fi

    chown "$user:$user" "$sshDir"
    chmod 700 "$sshDir"
    touch "$authorizedKeys"
    chown "$user:$user" "$authorizedKeys"
    chmod 600 "$authorizedKeys"

    if [ ! -f "$sshDir/id_rsa" ]; then
        echo "Generating RSA key for $user."

        if ! sudo -u "$user" ssh-keygen -q -t rsa -b 2048 -N "" -f "$sshDir/id_rsa"; then
            echo "ERROR: Failed to generate RSA key for $user."
            exit 1
        fi
    else
        echo "$user already has an RSA key."
    fi

    if [ ! -f "$sshDir/id_ed25519" ]; then
        echo "Generating Ed25519 key for $user."

        if ! sudo -u "$user" ssh-keygen -q -t ed25519 -N "" -f "$sshDir/id_ed25519"; then
            echo "ERROR: Failed to generate Ed25519 key for $user."
            exit 1
        fi
    else
        echo "$user already has an Ed25519 key."
    fi

    for publicKey in "$sshDir/id_rsa.pub" "$sshDir/id_ed25519.pub"; do
        if ! grep -qxF "$(cat "$publicKey")" "$authorizedKeys"; then
            cat "$publicKey" >> "$authorizedKeys"
            echo "Added $(basename "$publicKey") to $user's authorized_keys."
        else
            echo "$(basename "$publicKey") is already in $user's authorized_keys."
        fi
    done

    chown -R "$user:$user" "$sshDir"
done

dennisPublicKey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
dennisAuthorizedKeys="/home/dennis/.ssh/authorized_keys"

if grep -qxF "$dennisPublicKey" "$dennisAuthorizedKeys"; then
    echo
    echo "Dennis's supplied public key is already authorized."
else
    echo "$dennisPublicKey" >> "$dennisAuthorizedKeys"
    chown dennis:dennis "$dennisAuthorizedKeys"
    chmod 600 "$dennisAuthorizedKeys"

    echo
    echo "Added the supplied public key for dennis."
fi

echo
echo "========================================"
echo " Configuration completed successfully"
echo "========================================"
