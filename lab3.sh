#!/bin/bash

# This script copies configure-host.sh to both servers
# and then runs it on them.

verboseoption=""

# Check whether lab3.sh was run with -verbose
if [ "$1" = "-verbose" ]
then
    verboseoption="-verbose"
elif [ -n "$1" ]
then
    echo "Error: unknown option $1" >&2
    exit 1
fi

# Make sure configure-host.sh exists
if [ ! -f configure-host.sh ]
then
    echo "Error: configure-host.sh was not found" >&2
    exit 1
fi

# Make sure configure-host.sh is executable
if [ ! -x configure-host.sh ]
then
    echo "Error: configure-host.sh is not executable" >&2
    exit 1
fi

# Test server1 before copying
ssh remoteadmin@server1-mgmt "echo connected" > /dev/null

if [ $? -ne 0 ]
then
    echo "Error: could not connect to server1-mgmt" >&2
    exit 1
fi

# Copy script to server1
scp configure-host.sh remoteadmin@server1-mgmt:/tmp/configure-host.sh

if [ $? -ne 0 ]
then
    echo "Error: could not copy script to server1" >&2
    exit 1
fi

# Move it into /root and make it executable
ssh remoteadmin@server1-mgmt \
    "sudo cp /tmp/configure-host.sh /root/configure-host.sh && sudo chmod +x /root/configure-host.sh"

if [ $? -ne 0 ]
then
    echo "Error: could not install script on server1" >&2
    exit 1
fi

# Run it on server1
ssh remoteadmin@server1-mgmt -- \
    sudo /root/configure-host.sh $verboseoption \
    -name loghost \
    -ip 192.168.16.3 \
    -hostentry webhost 192.168.16.4

if [ $? -ne 0 ]
then
    echo "Error: configuration failed on server1" >&2
    exit 1
fi

# Test server2 before copying
ssh remoteadmin@server2-mgmt "echo connected" > /dev/null

if [ $? -ne 0 ]
then
    echo "Error: could not connect to server2-mgmt" >&2
    exit 1
fi

# Copy script to server2
scp configure-host.sh remoteadmin@server2-mgmt:/tmp/configure-host.sh

if [ $? -ne 0 ]
then
    echo "Error: could not copy script to server2" >&2
    exit 1
fi

# Move it into /root and make it executable
ssh remoteadmin@server2-mgmt \
    "sudo cp /tmp/configure-host.sh /root/configure-host.sh && sudo chmod +x /root/configure-host.sh"

if [ $? -ne 0 ]
then
    echo "Error: could not install script on server2" >&2
    exit 1
fi

# Run it on server2
ssh remoteadmin@server2-mgmt -- \
    sudo /root/configure-host.sh $verboseoption \
    -name webhost \
    -ip 192.168.16.4 \
    -hostentry loghost 192.168.16.3

if [ $? -ne 0 ]
then
    echo "Error: configuration failed on server2" >&2
    exit 1
fi

# Update the desktop VM's /etc/hosts file
sudo ./configure-host.sh $verboseoption \
    -hostentry loghost 192.168.16.3

if [ $? -ne 0 ]
then
    echo "Error: could not add loghost to the local computer" >&2
    exit 1
fi

sudo ./configure-host.sh $verboseoption \
    -hostentry webhost 192.168.16.4

if [ $? -ne 0 ]
then
    echo "Error: could not add webhost to the local computer" >&2
    exit 1
fi

if [ "$verboseoption" = "-verbose" ]
then
    echo "Lab 3 configuration finished successfully"
fi

exit 0
