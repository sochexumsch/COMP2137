#!/bin/bash

# Ignore TERM, HUP, and INT
trap '' TERM HUP INT

verbose=0

# The LAN interface on the servers is eth1
interface="eth1"

# The netplan file on the servers
netplanfile="/etc/netplan/10-lxc.yaml"

# This script needs root permissions
if [ "$EUID" -ne 0 ]
then
    echo "Error: run this script as root" >&2
    exit 1
fi

# Go through all command line options
while [ $# -gt 0 ]
do
    if [ "$1" = "-verbose" ]
    then
        verbose=1
        shift

    elif [ "$1" = "-name" ]
    then
        if [ -z "$2" ]
        then
            echo "Error: -name needs a hostname" >&2
            exit 1
        fi

        newname="$2"
        oldname=$(cat /etc/hostname)

        if [ "$oldname" = "$newname" ]
        then
            if [ "$verbose" -eq 1 ]
            then
                echo "The hostname is already $newname"
            fi
        else
            echo "$newname" > /etc/hostname

            if [ $? -ne 0 ]
            then
                echo "Error: could not update /etc/hostname" >&2
                exit 1
            fi

            hostnamectl set-hostname "$newname"

            if [ $? -ne 0 ]
            then
                echo "Error: could not change the running hostname" >&2
                exit 1
            fi

            # Change only the LAN hostname entry.
            # Do not change server1-mgmt or server2-mgmt.
            sed -i "/^192\.168\.16\./s/$oldname/$newname/" /etc/hosts

            if [ $? -ne 0 ]
            then
                echo "Error: could not update /etc/hosts" >&2
                exit 1
            fi

            logger "Changed hostname from $oldname to $newname"

            if [ "$verbose" -eq 1 ]
            then
                echo "Changed hostname from $oldname to $newname"
            fi
        fi

        shift 2

    elif [ "$1" = "-ip" ]
    then
        if [ -z "$2" ]
        then
            echo "Error: -ip needs an IP address" >&2
            exit 1
        fi

        newip="$2"

        oldip=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d/ -f1)

        if [ "$oldip" = "$newip" ]
        then
            if [ "$verbose" -eq 1 ]
            then
                echo "The IP address is already $newip"
            fi
        else
            if [ ! -f "$netplanfile" ]
            then
                echo "Error: netplan file was not found" >&2
                exit 1
            fi

            # Replace the old LAN IP in the netplan file
            sed -i "s/$oldip\/24/$newip\/24/" "$netplanfile"

            if [ $? -ne 0 ]
            then
                echo "Error: could not update the netplan file" >&2
                exit 1
            fi

            # Replace the old LAN IP in /etc/hosts
            sed -i "s/^$oldip /$newip /" /etc/hosts

            if [ $? -ne 0 ]
            then
                echo "Error: could not update /etc/hosts" >&2
                exit 1
            fi

            netplan apply

            if [ $? -ne 0 ]
            then
                echo "Error: netplan could not apply the new IP" >&2
                exit 1
            fi

            logger "Changed $interface IP address from $oldip to $newip"

            if [ "$verbose" -eq 1 ]
            then
                echo "Changed $interface IP address from $oldip to $newip"
            fi
        fi

        shift 2

    elif [ "$1" = "-hostentry" ]
    then
        if [ -z "$2" ] || [ -z "$3" ]
        then
            echo "Error: -hostentry needs a hostname and IP address" >&2
            exit 1
        fi

        hostnamewanted="$2"
        ipwanted="$3"

        # Check whether the exact entry is already present
        grep -q "^$ipwanted[[:space:]]\+$hostnamewanted$" /etc/hosts

        if [ $? -eq 0 ]
        then
            if [ "$verbose" -eq 1 ]
            then
                echo "$hostnamewanted is already in /etc/hosts with IP $ipwanted"
            fi
        else
            # Check whether the hostname is already present with another IP
            grep -q "[[:space:]]$hostnamewanted$" /etc/hosts

            if [ $? -eq 0 ]
            then
                # Replace the old entry
                sed -i "/[[:space:]]$hostnamewanted$/c\\$ipwanted $hostnamewanted" /etc/hosts

                if [ $? -ne 0 ]
                then
                    echo "Error: could not update $hostnamewanted in /etc/hosts" >&2
                    exit 1
                fi

                logger "Updated host entry for $hostnamewanted to $ipwanted"

                if [ "$verbose" -eq 1 ]
                then
                    echo "Updated $hostnamewanted to use IP $ipwanted"
                fi
            else
                # Add a new entry
                echo "$ipwanted $hostnamewanted" >> /etc/hosts

                if [ $? -ne 0 ]
                then
                    echo "Error: could not add $hostnamewanted to /etc/hosts" >&2
                    exit 1
                fi

                logger "Added host entry $ipwanted $hostnamewanted"

                if [ "$verbose" -eq 1 ]
                then
                    echo "Added $ipwanted $hostnamewanted to /etc/hosts"
                fi
            fi
        fi

        shift 3

    else
        echo "Error: unknown option $1" >&2
        exit 1
    fi
done

exit 0
