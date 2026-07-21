#!/bin/bash

# COMP2137 Assignment 2
# Lucas Shering
# This script configures server1

# Check if the script is being run as root

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: You need to run this script as root."
    exit 1
fi

echo "Running as root."

echo
echo "====================="
echo "NETWORK CONFIGURATION"
echo "====================="

netplanfile="/etc/netplan/10-lxc.yaml"

if [ ! -f "$netplanfile" ]; then
    echo "ERROR: Could not find $netplanfile"
    exit 1
fi

# Check whether the new address is already in the Netplan file

if grep -q "192.168.16.21/24" "$netplanfile"; then
    echo "The correct IP address is already in the Netplan file."
else
    echo "Changing the server IP address."

    sed -i 's/192\.168\.16\.[0-9]*\/24/192.168.16.21\/24/' "$netplanfile"

    if grep -q "192.168.16.21/24" "$netplanfile"; then
        echo "The Netplan file was changed."
    else
        echo "ERROR: The Netplan file was not changed."
        exit 1
    fi
fi

echo "Checking the Netplan file."

netplan generate

if [ "$?" != "0" ]; then
    echo "ERROR: The Netplan configuration is not valid."
    exit 1
fi

# Apply Netplan if the live address is not correct

if ip address show eth1 | grep -q "192.168.16.21/24"; then
    echo "eth1 already has the correct live address."
else
    echo "Applying the Netplan configuration."

    netplan apply

    if [ "$?" != "0" ]; then
        echo "ERROR: Netplan could not be applied."
        exit 1
    fi

    echo "Netplan was applied."
fi

echo
echo "=========="
echo "HOSTS FILE"
echo "=========="

# Check whether /etc/hosts is already completely correct

correcthost=$(grep -cE '^192\.168\.16\.21[[:space:]]+server1([[:space:]]|$)' /etc/hosts)
allserver1=$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+server1([[:space:]]|$)' /etc/hosts)

if [ "$correcthost" = "1" ] && [ "$allserver1" = "1" ]; then
    echo "/etc/hosts already has the correct server1 entry."
else
    echo "Removing old server1 entries from /etc/hosts."

    sed -i '/^[0-9][0-9.]*[[:space:]]\+server1\([[:space:]]\|$\)/d' /etc/hosts

    echo "192.168.16.21 server1" >> /etc/hosts

    if grep -qE '^192\.168\.16\.21[[:space:]]+server1([[:space:]]|$)' /etc/hosts; then
        echo "The server1 entry was added."
    else
        echo "ERROR: Could not update /etc/hosts."
        exit 1
    fi
fi

echo
echo "========"
echo "SOFTWARE"
echo "========"

echo "Updating package information."

apt-get update

if [ "$?" != "0" ]; then
    echo "ERROR: apt-get update failed."
    exit 1
fi

# Install Apache

if dpkg -s apache2 >/dev/null 2>&1; then
    echo "apache2 is already installed."
else
    echo "Installing apache2."

    apt-get install -y apache2

    if [ "$?" != "0" ]; then
        echo "ERROR: apache2 could not be installed."
        exit 1
    fi
fi

# Install Squid

if dpkg -s squid >/dev/null 2>&1; then
    echo "squid is already installed."
else
    echo "Installing squid."

    apt-get install -y squid

    if [ "$?" != "0" ]; then
        echo "ERROR: squid could not be installed."
        exit 1
    fi
fi

echo
echo "========"
echo "SERVICES"
echo "========"

# Start Apache if it is not running

if systemctl is-active --quiet apache2; then
    echo "apache2 is already running."
else
    echo "Starting apache2."

    systemctl start apache2

    if [ "$?" != "0" ]; then
        echo "ERROR: apache2 could not be started."
        exit 1
    fi
fi

# Start Squid if it is not running

if systemctl is-active --quiet squid; then
    echo "squid is already running."
else
    echo "Starting squid."

    systemctl start squid

    if [ "$?" != "0" ]; then
        echo "ERROR: squid could not be started."
        exit 1
    fi
fi

echo
echo "============="
echo "USER ACCOUNTS"
echo "============="

users="dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda"

for user in $users; do
    echo
    echo "Checking user $user."

    # Create the user if needed

    if id "$user" >/dev/null 2>&1; then
        echo "$user already exists."
    else
        echo "Creating $user."

        useradd -m -s /bin/bash "$user"

        if [ "$?" != "0" ]; then
            echo "ERROR: Could not create $user."
            exit 1
        fi
    fi

    # Make sure the home directory is correct

    userhome=$(getent passwd "$user" | cut -d: -f6)

    if [ "$userhome" != "/home/$user" ]; then
        echo "Fixing the home directory for $user."

        usermod -d "/home/$user" -m "$user"

        if [ "$?" != "0" ]; then
            echo "ERROR: Could not fix the home directory for $user."
            exit 1
        fi
    else
        echo "$user has the correct home directory."
    fi

    # Make sure Bash is the user's shell

    usershell=$(getent passwd "$user" | cut -d: -f7)

    if [ "$usershell" != "/bin/bash" ]; then
        echo "Changing the shell for $user."

        usermod -s /bin/bash "$user"

        if [ "$?" != "0" ]; then
            echo "ERROR: Could not change the shell for $user."
            exit 1
        fi
    else
        echo "$user already uses Bash."
    fi
done

echo
echo "Checking sudo access for dennis."

if groups dennis | grep -qw sudo; then
    echo "dennis is already in the sudo group."
else
    usermod -aG sudo dennis

    if [ "$?" != "0" ]; then
        echo "ERROR: Could not add dennis to sudo."
        exit 1
    fi

    echo "dennis was added to sudo."
fi

echo
echo "========"
echo "SSH KEYS"
echo "========"

for user in $users; do
    echo
    echo "Setting up SSH for $user."

    sshdir="/home/$user/.ssh"
    authfile="/home/$user/.ssh/authorized_keys"

    mkdir -p "$sshdir"

    if [ "$?" != "0" ]; then
        echo "ERROR: Could not create the SSH directory for $user."
        exit 1
    fi

    touch "$authfile"

    chown "$user:$user" "$sshdir"
    chown "$user:$user" "$authfile"

    chmod 700 "$sshdir"
    chmod 600 "$authfile"

    # Create RSA key

    if [ -f "$sshdir/id_rsa" ]; then
        echo "$user already has an RSA key."
    else
        echo "Creating an RSA key for $user."

        sudo -u "$user" ssh-keygen -q -t rsa -b 2048 -N "" \
            -f "$sshdir/id_rsa"

        if [ "$?" != "0" ]; then
            echo "ERROR: Could not create the RSA key for $user."
            exit 1
        fi
    fi

    # Create Ed25519 key

    if [ -f "$sshdir/id_ed25519" ]; then
        echo "$user already has an Ed25519 key."
    else
        echo "Creating an Ed25519 key for $user."

        sudo -u "$user" ssh-keygen -q -t ed25519 -N "" \
            -f "$sshdir/id_ed25519"

        if [ "$?" != "0" ]; then
            echo "ERROR: Could not create the Ed25519 key for $user."
            exit 1
        fi
    fi

    # Add RSA public key to authorized_keys

    rsakey=$(cat "$sshdir/id_rsa.pub")

    if grep -qxF "$rsakey" "$authfile"; then
        echo "The RSA public key is already authorized."
    else
        cat "$sshdir/id_rsa.pub" >> "$authfile"
        echo "The RSA public key was added."
    fi

    # Add Ed25519 public key to authorized_keys

    edkey=$(cat "$sshdir/id_ed25519.pub")

    if grep -qxF "$edkey" "$authfile"; then
        echo "The Ed25519 public key is already authorized."
    else
        cat "$sshdir/id_ed25519.pub" >> "$authfile"
        echo "The Ed25519 public key was added."
    fi

    chown -R "$user:$user" "$sshdir"
    chmod 700 "$sshdir"
    chmod 600 "$authfile"
done

echo
echo "Adding the supplied public key for dennis."

denniskey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
dennisauth="/home/dennis/.ssh/authorized_keys"

if grep -qxF "$denniskey" "$dennisauth"; then
    echo "The supplied key is already authorized for dennis."
else
    echo "$denniskey" >> "$dennisauth"

    chown dennis:dennis "$dennisauth"
    chmod 600 "$dennisauth"

    echo "The supplied key was added for dennis."
fi

echo
echo "======================"
echo "CONFIGURATION COMPLETE"
echo "======================"
