#!/bin/bash

NEW_HOSTNAME=$1

rm -f /opt/LifeKeeper/config/UNAME
rm -f /opt/LifeKeeper/config/networks
rm -f /opt/LifeKeeper/config/systems

hostname $NEW_HOSTNAME

echo -e "127.0.0.1\tlocalhost\t$NEW_HOSTNAME\n" > /etc/hosts
echo $NEW_HOSTNAME > /etc/hostname
echo $NEW_HOSTNAME > /etc/HOSTNAME

hostnamectl set-hostname --static $NEW_HOSTNAME