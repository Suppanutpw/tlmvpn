#!/bin/bash

# aws cli credential
region="us-east-1"
aws_access_key_id=""
aws_secret_access_key=""
# aws_session_token=""

# ใช้ api ดึง describe-instance มา เอาแค่ tunnel public ip ที่มี tag Service: vpnserver
aws configure set region "$region"
aws configure set aws_access_key_id "$aws_access_key_id"
aws configure set aws_secret_access_key "$aws_secret_access_key"
# aws configure set aws_session_token "$aws_session_token"

# สร้างไฟล์ config อัตโนมัติ
tempFile=transfer.tlm
logFile=tlmvpnClientStarter.log
ipsecFile=/etc/ipsec.conf
xl2tpdFile=/etc/xl2tpd/xl2tpd.conf
l2pdClientFile=/etc/ppp/options.l2tpd.client
secretKeyFile=/etc/ipsec.secrets
l2tpControlFile=/var/run/xl2tpd/l2tp-control

rm $ipsecFile
rm $xl2tpdFile

touch $logFile
touch $ipsecFile
touch $xl2tpdFile

while true;
do

	echo "Send Request for ec2 describe-instances"
	# ดึง public tunnel ของทุก vpn server มาด้วย cli
	VPNInstance=$(aws ec2 describe-instances --filters Name=tag:Service,Values=vpnserver Name=instance-state-name,Values=running)
	VPNIntCount=$(($(echo $VPNInstance | jq '.Reservations | length')))

	connList=(); connCount=0;
	dconList=(); dconCount=0;
	RESETCONNECT=0
	for i in $(seq 1 1 $VPNIntCount)
	do
	    VPNIntPublicIP=$(echo $VPNInstance | jq -r ".Reservations[$((i-1))].Instances[0].PublicIpAddress")

	    VPNIntTunnelIP=$(aws ec2 describe-instances --filters Name=tag:Service,Values=vpnserver Name=instance-state-name,Values=running --query "Reservations[$((i-1))].Instances[].[Tags[?Key=='TunnelIP']][0][0][0].Value")
	    VPNIntTunnelIP=$(echo $VPNIntTunnelIP | jq -r '.')

	    # ถ้า server ยังไม่ตั้งก็ยังไม่เชื่อมก่อน
	    if [[ $VPNIntTunnelIP == "0.0.0.0" || $VPNIntTunnelIP == "null" ]]; then
	    	continue
	    fi

		# ดูว่าที่เช็คอยู่เชื่อมมีอยู่แล้วรึปล่าว
		if [[ -s $ipsecFile ]]; then
			listPublicIP=( $(cat $ipsecFile | grep -Eo '([0-9]*\.){3}[0-9]*' | tr '\n' ' ') )
		else
			listPublicIP=()
		fi

		VPNIntTunnelIP="$(echo $VPNIntTunnelIP | grep -Eo '([0-9]*\.){2}[0-9]*').1"
		# เช็คว่าเป็นตัวใหม่ไหม
		if [[ " ${listPublicIP[*]} " =~ " $VPNIntPublicIP " ]]; then
			# ถ้ามีก็ ping 3 ครั้งเพื่อดูว่ายังเชื่อม tunnel ได้ไหม ถ้าไม่ได้ก็เชื่อมใหม่ โดยตั้งเวลา timeout ไว้ 1.5 วินาที
			# และมี ip อยู่ใน ifconfig
			PINGSUCCESSCOUNT=0
			TUNNELINT=$(ifconfig | grep -Eoc $VPNIntTunnelIP)
			for _ in $(seq 1 1 3)
			do
				if timeout 1.5 ping -c 1 "$VPNIntTunnelIP" &> /dev/null; then
					PINGSUCCESSCOUNT=$((PINGSUCCESSCOUNT+1))
				fi
			done

			if [[ $PINGSUCCESSCOUNT -ne 0 && TUNNELINT -ne 0 ]]; then
				# this mean there still have connection ก็ข้าม loop นี้ไปเช็คตัวต่อไปได้เลย
				continue
			fi

			# ถ้าไม่ก็เชื่อมใหม่ หา tlmvpn number
			tlmvpnName="-1"
			ipsecData=( $(cat $ipsecFile | grep 'conn tlmvpn\|right=') )
			for i in $(seq 0 3 $(( ${#ipsecData[@]} - 1 )) )
			do
				if [[ $VPNIntPublicIP == $(echo ${ipsecData[$((i+2))]} | grep -Eo '([0-9]*\.){3}[0-9]*') ]]; then
					tlmvpnName=${ipsecData[$((i+1))]} 
				fi
			done

			# ถ้าเจอใน ipsec.conf ก็เริ่มเชื่อมต่อใหม่
			if [[ $tlmvpnName != "-1" ]]; then

				# ไม่จำเป็นต้องตัดการเชื่อมต่อก็ได้ แต่ควรทำในกรณีฝั่ง client ไม่เสถียร
				dconList[$((dconCount))]=$tlmvpnName
				dconCount=$((dconCount + 1))

				connList[$((connCount))]=$tlmvpnName
				connCount=$((connCount + 1))
			else
				echo "$(date '+%d/%m/%Y %H:%M:%S') cannot find query connection in ipsec.conf file" >> $logFile
			fi

		else

			# reset list of connect because we gonna reset all connection
			RESETCONNECT=1

			# connection ที่เกิดใหม่ จะสร้าง config ในไฟล์ ipsec.conf กับ xl2tpd.conf เพิ่ม
			VPNCOUNT=$(cat $ipsecFile | grep -Eoc "conn tlmvpn")
			VPNCOUNT=$((VPNCOUNT+1)) # add new index

			echo "$(date '+%d/%m/%Y %H:%M:%S') new vpn server from: public $VPNIntPublicIP tunnel $VPNIntTunnelIP $((VPNCOUNT))" >> $logFile

			# add ipsec.conf
			{
				echo "conn tlmvpn$((VPNCOUNT))";
				echo "  auto=add";
				echo "  keyexchange=ikev1";
				echo "  authby=secret";
				echo "  type=transport";
				echo "  left=%defaultroute";
				echo "  leftprotoport=17/1701";
				echo "  rightprotoport=17/1701";
				echo "  right=$VPNIntPublicIP";
				echo "  ike=aes128-sha1-modp2048";
				echo "  esp=aes128-sha1";
				echo ""
			} >> $ipsecFile

			# add xl2tpd.conf
			{
				echo "[lac tlmvpn$((VPNCOUNT))]";
				echo "lns = $VPNIntPublicIP";
				echo "ppp debug = yes";
				echo "pppoptfile = /etc/ppp/options.l2tpd.client";
				echo "length bit = yes";
				echo ""
			} >> $xl2tpdFile

		    # add new connection to list
			connCount=$((connCount + 1))
		fi

	done

	if [ $((RESETCONNECT)) -eq 1 ]; then
		echo "$(date '+%d/%m/%Y %H:%M:%S') reset connection for auto scaling" >> $logFile

		# RESTART SERVICE
		mkdir -p /var/run/xl2tpd
	    touch $l2tpControlFile
	    service strongswan restart
	    service strongswan-starter restart
	    service xl2tpd restart

		connList=(); connCount=0;
		dconList=(); dconCount=0;
		# disconnect all vpn before restart
		for i in $(seq 1 1 $VPNCOUNT)
		do
			dconList[$((dconCount))]="tlmvpn$i"
			dconCount=$((dconCount + 1))
		done

		for i in $(seq 1 1 $VPNIntCount)
		do
			VPNIntPublicIP=$(echo $VPNInstance | jq -r ".Reservations[$((i-1))].Instances[0].PublicIpAddress")
			# สร้าง list สำหรับเชื่อมต่อใหม่ ที่ยังมีชีวิตอยู่
			tlmvpnName="-1"
			ipsecData=( $(cat $ipsecFile | grep 'conn tlmvpn\|right=') )
			for i in $(seq 0 3 $(( ${#ipsecData[@]} - 1 )) )
			do
				if [[ $VPNIntPublicIP == $(echo ${ipsecData[$((i+2))]} | grep -Eo '([0-9]*\.){3}[0-9]*') ]]; then
					connList[$((connCount))]=${ipsecData[$((i+1))]} 
					connCount=$((connCount + 1))
				fi
			done
		done
	fi

	for dcon in ${dconList[@]}
	do
		echo "$(date '+%d/%m/%Y %H:%M:%S') disconnect with ipsec down $dcon" >> $logFile

		# ตั้งเวลาการตัดการเชื่อมต่อภายใน 3 วินาที
		timeout 3 bash -c "echo \"d $dcon\" > $l2tpControlFile && ipsec down \"$dcon\"" &&
		echo "$(date '+%d/%m/%Y %H:%M:%S') VPN Disconnect!!!" >> $logFile ||
		echo "$(date '+%d/%m/%Y %H:%M:%S') VPN Disconnect FAIL!!!" >> $logFile
	done

	# wait for disconnect timeout
	sleep 0.5

	# connection list
	for conn in ${connList[@]}
	do
		echo "$(date '+%d/%m/%Y %H:%M:%S') start connection with ipsec up $conn" >> $logFile

		# ตั้งเวลา timeout 3 วินาที สำหรับเชื่อมต่อ
	   	timeout 3 bash -c "ipsec up $conn && echo \"c $conn\" > $l2tpControlFile" &&
	    echo "$(date '+%d/%m/%Y %H:%M:%S') VPN Connect!!!" >> $logFile ||
	    echo "$(date '+%d/%m/%Y %H:%M:%S') VPN Connect FAIL!!!" >> $logFile
	done

	sleep 10

done
