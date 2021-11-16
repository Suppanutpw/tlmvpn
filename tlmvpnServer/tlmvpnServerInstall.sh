#!/bin/bash

# check that user must run as root
if [ $(( $(id -u) )) -ne 0 ]
    then echo "System Error: Please run as sudo command"
    exit 1
fi

yum -y update
yum -y install jq
yum -y install quagga

# install tlm ทะลุเมฆ vpn
mkdir /etc/tlmvpn

# ลง vpn server ของ hwdsl2
if [ ! -f "/etc/ppp/chap-secrets" ]; then
    wget https://git.io/vpnquickstart -O /etc/tlmvpn/vpn.sh && sudo sh /etc/tlmvpn/vpn.sh
fi

mv tlmvpnServer.sh /etc/tlmvpn/tlmvpnServer.sh

# init basic ospf
{
    echo ""
    echo "# Added by tlmvpn VPN script"
    echo "sudo nohup bash /etc/tlmvpn/tlmvpnServer.sh > /etc/tlmvpn/tlmvpnServer.log 2>&1 & echo $! > /var/run/tlmvpnServer.pid"
    echo "sudo service ospfd start" 
    echo "sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
    echo ""
} >> /etc/rc.local

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

chmod +x /etc/rc.d/rc.local

rm tlmvpnServer.zip
rm tlmvpnServerInstall.sh
