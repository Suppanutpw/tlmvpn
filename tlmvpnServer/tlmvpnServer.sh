#!/bin/bash

# aws cli
region="us-east-1"
# aws_access_key_id=""
# aws_secret_access_key=""
# aws_session_token=""

# ใช้ api ดึง describe-instance มา เอาแค่ private public ที่มีชื่อ vpnserver
aws configure set region "$region"
# aws configure set aws_access_key_id "$aws_access_key_id"
# aws configure set aws_secret_access_key "$aws_secret_access_key"
# aws configure set aws_session_token "$aws_session_token"

S3USERFILE=s3://tlm-gulugulu/vpnserver
S3SECRETFILE=s3://tlm-gulugulu/vpnserver

# เปลี่ยนเป็นไม่ต้อง trigger ก็ได้แต่ให้ server อ่าน tag ทุกๆ กี่วิก็ว่าไปน่าจะง่ายกว่า
USER="ec2-user"
TUNNELFILE="/etc/xl2tpd/xl2tpd.conf"
USERDBFILE="/etc/ppp/chap-secrets"
SECRETKEYFILE="/etc/ipsec.secrets"
LOGFILE="/etc/tlmvpn/tlmvpnServer.log"
HWDSLVPNFILE="/etc/tlmvpn/vpn.sh"
NATFILE="/etc/sysconfig/iptables"

S3LOCALFILE="/etc/tlmvpn"

sudo rm "$S3LOCALFILE"/ipsec.secrets
sudo rm "$S3LOCALFILE"/chap-secrets

# check that user must run as root
if [ $(( $(id -u) )) -ne 0 ]
    then echo "System Error: Please run as sudo command"
    #exit 1
fi

sudo sh $HWDSLVPNFILE

VPNInstance=$(aws ec2 describe-instances --filters Name=tag:Service,Values=vpnserver Name=instance-state-name,Values=running)
VPNIntCount=$(($(echo $VPNInstance | jq '.Reservations | length')))

# ถ้ามี instance ที่รันมากกว่าหรือเท่ากับ 2 หมายความว่าจะรัน second ได้
PUBLICIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATEIP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)

# ดึง public private id tunnel ของทุก vpn server มาด้วย cli
for i in $(seq 1 1 $VPNIntCount)
do
    VPNIntPublicIP[$((i))]=$(echo $VPNInstance | jq -r ".Reservations[$((i-1))].Instances[0].PublicIpAddress")
    VPNIntPrivateIP[$((i))]=$(echo $VPNInstance | jq -r ".Reservations[$((i-1))].Instances[0].PrivateIpAddress")

    VPNIntTunnelIP[$((i))]=$(aws ec2 describe-instances --filters Name=tag:Service,Values=vpnserver Name=instance-state-name,Values=running --query "Reservations[$((i-1))].Instances[].[Tags[?Key=='TunnelIP']][0][0][0].Value")
    VPNIntTunnelIP[$((i))]=$(echo ${VPNIntTunnelIP[$((i))]} | jq -r '.')
done

# หาดูว่ามี ip ไหนซ้ำบ้าง เอาที่ไม่ซ้ำไปประกาศ tunnel
newTunnelIP="10.253.0.0"
for i in $(seq 0 1 255)
do
    if [[ ! " ${VPNIntTunnelIP[*]} " =~ " 10.253.$i.0 " ]]; then
        newTunnelIP="10.253.$i.0"
        break
    fi
done

# ไปดึงไฟล์ user, share key มาจาก s3
sudo mkdir $S3LOCALFILE
aws s3 sync $S3USERFILE $S3LOCALFILE --exclude='*' --include='chap-secrets'
aws s3 sync $S3SECRETFILE $S3LOCALFILE --exclude='*' --include='ipsec.secrets'
sudo cp "$S3LOCALFILE"/chap-secrets $USERDBFILE
sudo cp "$S3LOCALFILE"/ipsec.secrets $SECRETKEYFILE

# aws s3 sync s3://gulugulu/vpnserver /etc/ppp --exclude='*' --include='*/chap-secrets'
# aws s3 cp s3://gulugulu/vpnserver/ipsec.secrets $SECRETKEYFILE

# แก้ไฟล์ /etc/xl2tpd/xl2tpd.conf (> is overwrite) เขียน ip tunnel ที่ได้ทับไป
newTunnelIPThridOctet=$(echo $newTunnelIP | grep -Eo '([0-9]*\.){2}[0-9]*')
{
    echo "[global]";
    echo "port = 1701";
    echo "";
    echo "[lns default]";
    echo "ip range = $newTunnelIPThridOctet.10-$newTunnelIPThridOctet.250";
    echo "local ip = $newTunnelIPThridOctet.1";
    echo "require chap = yes";
    echo "refuse pap = yes";
    echo "require authentication = yes";
    echo "name = l2tpd";
    echo "pppoptfile = /etc/ppp/options.xl2tpd";
    echo "length bit = yes"
} > $TUNNELFILE
sed -i "s/@/$newTunnelIPThridOctet/g" $USERDBFILE

# Gen New NAT Rule ถ้าแก้ ip octet ต้องมาแก้ใน NAT Rule ด้วย
# 192.168.0.0/16
# 172.16.0.0/12
# 10.0.0.0/8
{
    echo "# Modified by TLMVPN script";
    echo "*nat";
    echo ":PREROUTING ACCEPT [0:0]";
    echo ":INPUT ACCEPT [0:0]";
    echo ":OUTPUT ACCEPT [0:0]";
    echo ":POSTROUTING ACCEPT [0:0]";
    echo "-A POSTROUTING -s 10.0.0.0/8 -o eth0 -j MASQUERADE";
    echo "COMMIT";
} > $NATFILE
sudo iptables-restore < /etc/sysconfig/iptables

# restart config
service ipsec restart
service xl2tpd restart
sudo iptables -F

# เปลี่ยน id ของ vpnnew เป็น private ip แทน และประกาศ tunnel ใหม่
instanceID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --resources "$instanceID" --tags Key=Service,Value="vpnserver"
aws ec2 create-tags --resources "$instanceID" --tags Key=TunnelIP,Value="$newTunnelIP"
aws ec2 modify-instance-attribute --instance-id=$instanceID --no-source-dest-check

echo "$(date '+%d/%m/%Y %H:%M:%S') VPN Server Configuration Success" >> $LOGFILE

VPNInstance=$(aws ec2 describe-instances --filters Name=tag:Service,Values=vpnserver Name=instance-state-name,Values=running)
VPNIntCount=$(($(echo $VPNInstance | jq '.Reservations | length')))

while true;
do
    # if there have new file in S3
    USERDB=$(aws s3 sync $S3USERFILE $S3LOCALFILE --exclude='*' --include='chap-secrets')
    SECRETDB=$(aws s3 sync $S3SECRETFILE $S3LOCALFILE --exclude='*' --include='ipsec.secrets')

    # if there have new VPN Server Restart Service
    VPNInstance=$(aws ec2 describe-instances --filters Name=tag:Service,Values=vpnserver Name=instance-state-name,Values=running)
    VPNIntCountNew=$(($(echo $VPNInstance | jq '.Reservations | length')))

    if [[ ! -z $USERDB || ! -z $SECRETDB ]]; then
        sudo cp "$S3LOCALFILE"/chap-secrets $USERDBFILE
        sudo cp "$S3LOCALFILE"/ipsec.secrets $SECRETKEYFILE

        echo "$(date '+%d/%m/%Y %H:%M:%S') $USERDB" >> $LOGFILE
        echo "$(date '+%d/%m/%Y %H:%M:%S') $SECRETDB" >> $LOGFILE

        sed -i "s/@/$newTunnelIPThridOctet/g" $USERDBFILE

        service ipsec restart >> $LOGFILE
        service xl2tpd restart >> $LOGFILE
        sudo iptables -F
    elif [[ VPNIntCount -lt VPNIntCountNew ]] ; then
        echo "$(date '+%d/%m/%Y %H:%M:%S') restart all vpn service for auto scaling" >> $LOGFILE
        service ipsec restart >> $LOGFILE
        service xl2tpd restart >> $LOGFILE
        sudo iptables -F
    fi

    VPNIntCount=$(( $VPNIntCountNew ))

    sleep 30
done

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