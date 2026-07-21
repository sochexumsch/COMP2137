#!/bin/bash

# COMP2137 Assignment 2
# Lucas Shering
# This script configures server1

echo "Starting Assignment 2 script"

# Check for root

if [ "$(id -u)" -ne 0 ]; then
    echo "You must run this script as root"
    exit 1
fi

echo "Root check passed"

echo
echo "-------------"
echo "Network setup"
echo "-------------"

netplanfile="/etc/netplan/10-lxc.yaml"

if [ -f "$netplanfile" ]; then
    echo "Netplan file was found"
else
    echo "ERROR: Netplan file was not found"
    exit 1
fi

# Change the old 192.168.16 address to the new one

if grep -q "192.168.16.21/24" "$netplanfile"; then
    echo "The correct address is already in the Netplan file"
else
    echo "Changing the IP address"

    sed -i 's/192\.168\.16\.[0-9]*\/24/192.168.16.21\/24/' "$netplanfile"

    if grep -q "192.168.16.21/24" "$netplanfile"; then
        echo "The IP address was changed"
    else
        echo "ERROR: The IP address was not changed"
        exit 1
    fi
fi

echo "Checking the Netplan file"

netplan generate

if [ "$?" -ne 0 ]; then
    echo "ERROR: Netplan configuration is not valid"
    exit 1
fi

echo "Netplan configuration is valid"

# Apply Netplan if eth1 does not have the correct address

if ip address show eth1 | grep -q "192.168.16.21/24"; then
    echo "eth1 already has the correct address"
else
    echo "Applying Netplan"

    netplan apply

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Netplan could not be applied"
        exit 1
    fi

    echo "Netplan was applied"
fi

echo
echo "----------------"
echo "Hosts file setup"
echo "----------------"

# Remove any old IPv4 entries for server1

echo "Removing old server1 entries"

sed -i '/^[0-9][0-9.]*[[:space:]]\+server1\([[:space:]]\|$\)/d' /etc/hosts

if [ "$?" -ne 0 ]; then
    echo "ERROR: Could not remove old server1 entries"
    exit 1
fi

echo "192.168.16.21 server1" >> /etc/hosts

if grep -qE '^192\.168\.16\.21[[:space:]]+server1([[:space:]]|$)' /etc/hosts; then
    echo "The correct server1 entry is in /etc/hosts"
else
    echo "ERROR: Could not add server1 to /etc/hosts"
    exit 1
fi

echo
echo "-------------------"
echo "Installing software"
echo "-------------------"

echo "Updating package lists"

apt-get update

if [ "$?" -ne 0 ]; then
    echo "ERROR: apt-get update failed"
    exit 1
fi

# Apache

if dpkg -s apache2 >/dev/null 2>&1; then
    echo "Apache is already installed"
else
    echo "Installing Apache"

    apt-get install -y apache2

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Apache could not be installed"
        exit 1
    fi

    echo "Apache was installed"
fi

# Squid

if dpkg -s squid >/dev/null 2>&1; then
    echo "Squid is already installed"
else
    echo "Installing Squid"

    apt-get install -y squid

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Squid could not be installed"
        exit 1
    fi

    echo "Squid was installed"
fi

echo
echo "-----------------"
echo "Starting services"
echo "-----------------"

# Apache service

if systemctl is-active --quiet apache2; then
    echo "Apache is already running"
else
    echo "Starting Apache"

    systemctl start apache2

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Apache could not be started"
        exit 1
    fi

    echo "Apache is running"
fi

# Squid service

if systemctl is-active --quiet squid; then
    echo "Squid is already running"
else
    echo "Starting Squid"

    systemctl start squid

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Squid could not be started"
        exit 1
    fi

    echo "Squid is running"
fi

echo
echo "--------------"
echo "Creating users"
echo "--------------"

users="dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda"

for user in $users
do
    echo
    echo "Checking $user"

    if id "$user" >/dev/null 2>&1; then
        echo "$user already exists"
    else
        echo "Creating $user"

        useradd -m -s /bin/bash "$user"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not create $user"
            exit 1
        fi

        echo "$user was created"
    fi

    # Check home directory

    homefolder=$(getent passwd "$user" | cut -d: -f6)

    if [ "$homefolder" = "/home/$user" ]; then
        echo "$user has the correct home directory"
    else
        echo "Changing the home directory for $user"

        usermod -d "/home/$user" -m "$user"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not change the home directory for $user"
            exit 1
        fi
    fi

    # Check shell

    shell=$(getent passwd "$user" | cut -d: -f7)

    if [ "$shell" = "/bin/bash" ]; then
        echo "$user already uses Bash"
    else
        echo "Changing the shell for $user"

        usermod -s /bin/bash "$user"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not change the shell for $user"
            exit 1
        fi
    fi
done

echo
echo "Checking sudo access for dennis"

groups dennis | grep -qw sudo

if [ "$?" -eq 0 ]; then
    echo "dennis is already in the sudo group"
else
    echo "Adding dennis to the sudo group"

    usermod -aG sudo dennis

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Could not add dennis to sudo"
        exit 1
    fi

    echo "dennis was added to sudo"
fi

echo
echo "-----------------"
echo "Creating SSH keys"
echo "-----------------"

for user in $users
do
    echo
    echo "Setting up SSH for $user"

    sshfolder="/home/$user/.ssh"
    authorizedfile="/home/$user/.ssh/authorized_keys"

    # Create the .ssh directory

    if [ -d "$sshfolder" ]; then
        echo ".ssh directory already exists"
    else
        mkdir -p "$sshfolder"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not create .ssh for $user"
            exit 1
        fi

        echo ".ssh directory was created"
    fi

    touch "$authorizedfile"

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Could not create authorized_keys for $user"
        exit 1
    fi

    chown "$user:$user" "$sshfolder"
    chown "$user:$user" "$authorizedfile"

    chmod 700 "$sshfolder"
    chmod 600 "$authorizedfile"

    # RSA key

    if [ -f "$sshfolder/id_rsa" ]; then
        echo "RSA key already exists"
    else
        echo "Creating RSA key"

        sudo -u "$user" ssh-keygen -q -t rsa -b 2048 -N "" -f "$sshfolder/id_rsa"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not create RSA key for $user"
            exit 1
        fi

        echo "RSA key was created"
    fi

    # Ed25519 key

    if [ -f "$sshfolder/id_ed25519" ]; then
        echo "Ed25519 key already exists"
    else
        echo "Creating Ed25519 key"

        sudo -u "$user" ssh-keygen -q -t ed25519 -N "" -f "$sshfolder/id_ed25519"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not create Ed25519 key for $user"
            exit 1
        fi

        echo "Ed25519 key was created"
    fi

    # Add RSA public key

    rsakey=$(cat "$sshfolder/id_rsa.pub")

    grep -qxF "$rsakey" "$authorizedfile"

    if [ "$?" -eq 0 ]; then
        echo "RSA public key is already in authorized_keys"
    else
        cat "$sshfolder/id_rsa.pub" >> "$authorizedfile"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not add RSA key for $user"
            exit 1
        fi

        echo "RSA public key was added"
    fi

    # Add Ed25519 public key

    edkey=$(cat "$sshfolder/id_ed25519.pub")

    grep -qxF "$edkey" "$authorizedfile"

    if [ "$?" -eq 0 ]; then
        echo "Ed25519 public key is already in authorized_keys"
    else
        cat "$sshfolder/id_ed25519.pub" >> "$authorizedfile"

        if [ "$?" -ne 0 ]; then
            echo "ERROR: Could not add Ed25519 key for $user"
            exit 1
        fi

        echo "Ed25519 public key was added"
    fi

    chown -R "$user:$user" "$sshfolder"
    chmod 700 "$sshfolder"
    chmod 600 "$authorizedfile"
done

echo
echo "-------------------------------"
echo "Adding the extra key for dennis"
echo "-------------------------------"

denniskey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
dennisfile="/home/dennis/.ssh/authorized_keys"

grep -qxF "$denniskey" "$dennisfile"

if [ "$?" -eq 0 ]; then
    echo "The supplied key is already there"
else
    echo "$denniskey" >> "$dennisfile"

    if [ "$?" -ne 0 ]; then
        echo "ERROR: Could not add the supplied key for dennis"
        exit 1
    fi

    chown dennis:dennis "$dennisfile"
    chmod 600 "$dennisfile"

    echo "The supplied key was added"
fi

echo
echo "---------------"
echo "script finished"
echo "---------------"
