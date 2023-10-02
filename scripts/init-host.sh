#!/bin/bash

NODE1=$1
NODE2=$2
IP1=$3
IP2=$4

echo -e "$IP1\t$NODE1\n" >> /etc/hosts
echo -e "$IP2\t$NODE2\n" >> /etc/hosts
export PATH=$PATH:/usr/local/bin