#!/bin/bash

# check flag syntax
PIDFILE=/var/run/tlmvpnClientStarter.pid
NOHUPFILE=tlmvpnClientStarter.log
STARTERFILE=tlmvpnClientStarter.sh
ipsecFile=/etc/ipsec.conf
l2pdClientFile=/etc/ppp/options.l2tpd.client
l2tpControlFile=/var/run/xl2tpd/l2tp-control
secretKeyFile=/etc/ipsec.secrets

# check that user must run as root
if [ $(( $(id -u) )) -ne 0 ]
    then echo "System Error: Please run as sudo command"
    exit 1
fi

while getopts "m:u:p:k:" flag;
do
    case "${flag}" in
        m) MODE=${OPTARG};;
        u) USER=${OPTARG};;
        p) PASS=${OPTARG};;
        k) SECRET=${OPTARG};;
    esac
done

if [[ ! -z "$USER" && ! -z "$PASS" ]]; then
    {
        echo "ipcp-accept-local";
        echo "ipcp-accept-remote";
        echo "refuse-eap";
        echo "require-chap";
        echo "noccp";
        echo "noauth";
        echo "mtu 1280";
        echo "mru 1280";
        echo "noipdefault";
        echo "defaultroute";
        echo "usepeerdns";
        echo "connect-delay 5000";
        echo "name \"$USER\"";
        echo "password \"$PASS\""
        echo ""
    } > $l2pdClientFile
    echo "Updated $l2pdClientFile"
fi

if [ ! -z "$SECRET" ]; then
    {
        echo ": PSK \"$SECRET\"";
        echo ""
    } > $secretKeyFile
    echo "Updated $secretKeyFile"
fi

if [ -z $MODE  ]; then
    echo "Warning: System not Start Require -m Flag"
    exit 1
fi

if [[ $MODE == "start" ]]; then
    nohup bash $STARTERFILE > $NOHUPFILE 2>&1 & echo $! > $PIDFILE
    echo "Started tlmvpn pid: $(cat $PIDFILE)"
elif [ $MODE == "stop" ]; then
    kill -9 $(cat $PIDFILE)
    VPNCOUNT=$(cat $ipsecFile | grep -Eoc "conn tlmvpn")

    # disconnect all vpn before restart
    for i in $(seq 1 1 $VPNCOUNT)
    do
        # ตั้งเวลาการตัดการเชื่อมต่อภายใน 3 วินาที
        timeout 3 bash -c "echo \"d tlmvpn$i\" > $l2tpControlFile && ipsec down \"tlmvpn$i\"" &&
        echo "$(date '+%d/%m/%Y %H:%M:%S') VPN tlmvpn$i Disconnect!!!" ||
        echo "$(date '+%d/%m/%Y %H:%M:%S') VPN tlmvpn$i Disconnect FAIL!!!"
    done

    mkdir -p /var/run/xl2tpd &&
    touch $l2tpControlFile &&
    service strongswan-starter restart &&
    service xl2tpd restart

    echo "Stopped tlmvpn"
elif [ $MODE == "restart" ]; then
    kill -9 $(cat $PIDFILE)
    VPNCOUNT=$(cat $ipsecFile | grep -Eoc "conn tlmvpn")

    # disconnect all vpn before restart
    for i in $(seq 1 1 $VPNCOUNT)
    do
        # ตั้งเวลาการตัดการเชื่อมต่อภายใน 3 วินาที
        timeout 3 bash -c "echo \"d tlmvpn$i\" > $l2tpControlFile && ipsec down \"tlmvpn$i\"" &&
        echo "$(date '+%d/%m/%Y %H:%M:%S') VPN tlmvpn$i Disconnect!!!" ||
        echo "$(date '+%d/%m/%Y %H:%M:%S') VPN tlmvpn$i Disconnect FAIL!!!"
    done
    echo "Stopped tlmvpn"

    mkdir -p /var/run/xl2tpd &&
    touch $l2tpControlFile &&
    service strongswan-starter restart &&
    service xl2tpd restart

    nohup bash $STARTERFILE > $NOHUPFILE 2>&1 & echo $! > $PIDFILE
    echo "Started tlmvpn pid: $(cat $PIDFILE)"
else
    echo "Syntax Error: Unknown -m Flag Mode"
    exit 1
fi

########################################################
#    และสุดท้ายนี้จงละทิ้งโลจิกแล้วนั่งสมาธิทำใจให้สงบบัคจะไม่เกิด    #
#                        _oo0oo_                       #
#                       o8888888o                      #
#                       88" . "88                      #
#                       (| -_- |)                      #
#                       0\  =  /0                      #
#                     ___/`---'\___                    #
#                   .' \|     |// '.                   #
#                  / \|||  :  |||// \                  #
#                 / _||||| -:- |||||- \                #
#                |   | \\  -  /// |   |                #
#                | \_|  ''\---/''  |_/ |               #
#                \  .-\__  '-'  ___/-. /               #
#              ___'. .'  /--.--\  `. .'___             #
#           ."" '<  `.___\_<|>_/___.' >' "".           #
#          | | :  `- \`.;`\ _ /`;.`/ - ` : | |         #
#          \  \ `_.   \_ __\ /__ _/   .-` /  /         #
#===========`-.____`.___ \_____/___.-`___.-'===========#
#                        `=---='                       #
