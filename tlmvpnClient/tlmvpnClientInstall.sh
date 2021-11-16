#!/bin/bash

# check that user must run as root
if [ $(( $(id -u) )) -ne 0 ]
    then echo "System Error: Please run as sudo command"
    exit 1
fi

apt-get -y update
apt-get -y install strongswan xl2tpd net-tools
apt-get -y install jq
apt-get -y install quagga

# install aws
aws --version || { 
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &&
	unzip awscliv2.zip &&
	sudo ./aws/install &&
	echo "installed aws cli v2"
}

# install tlm ทะลุเมฆ vpn
mkdir /etc/tlmvpn

mv tlmvpnClientStarter.sh /etc/tlmvpn/tlmvpnClientStarter.sh
mv tlmvpnClient.sh /etc/tlmvpn/tlmvpnClient.sh

# init basic ospf
touch /etc/quagga/daemons
{
    echo "ospfd=yes"
    echo "zebra=yes"
    echo ""
} > /etc/quagga/daemons

touch /etc/quagga/zebra.conf
ifaddress=($(ifconfig | grep -Eo '(addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | tr '\n' ' ' | tr '.' '-'))
{
    echo "hostname tlmvpn-${ifaddress[0]}"
    echo ""
} > /etc/quagga/zebra.conf

touch /etc/quagga/ospfd.conf
{
    echo "!";
    echo "log file /etc/quagga/ospfd.log";
    echo "router ospf";
    echo " auto-cost reference-bandwidth 1000";
    echo " network 0.0.0.0/0 area 0.0.0.0";
    echo "!"
} > /etc/quagga/ospfd.conf

rm tlmvpnClient.zip
rm tlmvpnClientInstall.sh
