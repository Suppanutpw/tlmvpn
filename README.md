# TLMVPN
## _Manual AWS Transit Gateway_
[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)

Service VPN ที่กลุ่มเรานำมาใช้: https://github.com/hwdsl2/setup-ipsec-vpn
Video Demo: https://youtu.be/Gv64-j1zkVw

## VPN server Installation (ec2 linux)

เริ่มแรกต้องเตรียม s3 bucket, iam role สำหรับ vpnserver, iam user สำหรับ vpnclient โดยกำหนดสิทธิ์ให้เข้าถึง ec2, s3 ได้ (หากต้องการ least privilege ศึกษาในโค้ดเพิ่มเติม)

**1. สร้าง Environment โดยแยก VPC ระหว่างตัว VPN server กับ VPN Client**

**2. ลง tlmvpn service ในเครื่อง server**


สร้างโฟลเดอร์ vpnserver ใน s3 bucket ที่คุณกำหนดไว้
เอาไฟล์ chap-secrets กับ ipsec.secrets ใส่ในโฟลเดอร์นั้น
**ตัวอย่างไฟล์ chap-secrets ตัวเลขคือ IP Octect สุดท้าย โดยเลือกได้ตั้งแต่เลข 10-250**
```
"username1" l2tpd "password2" @.10
"username2" l2tpd "password2" @.11
"username3" l2tpd "password3" @.12
```

**ตัวอย่างไฟล์ ipsec.secrets**
```
%any  %any  : PSK "pre-shared-key"
```

ผู้ใช้ต้องรันใน mode root ด้วยคำสั่ง `sudo su` ก่อนจะลงโปรแกรม
```sh
curl -L -0 "https://git.io/JP0MJ" -o "tlmvpnServer.zip"
unzip tlmvpnServer.zip
sudo bash tlmvpnServerInstall.sh
```

### แก้โค้ดในไฟล์ tlmvpnServer.sh ด้วยคำสั่ง `nano /etc/tlmvpn/tlmvpnServer.sh`

ให้ตั้ง credential ของ aws cli ก่อนต้องแก้ตัวแปรดังต่อไปนี้ และ uncomment บรรทัด 10-13 ออก
- region (หากใช้ iam role กำหนดแค่ส่วนนี้)
- aws_access_key_id
- aws_secret_access_key
- aws_session_token

แก้ S3 directory url ไปยัง bucket ของคุณ ในไฟล์ โดยแก้ที่บรรทัดที่ 15-16
- S3USERFILE (path ไปยังไฟล์ chap-secrets) เช่น s3://gulugulu/vpnserver
- S3SECRETFILE (path ไปยังไฟล์ ipsec.secrets) เช่น s3://gulugulu/vpnserver

ทำการ reboot เครื่อง 1 รอบหลังจากนั้นสามารถใช้ระบบได้ตามปกติโดยไม่ต้องมีคำสั่งเพิ่มเติม
แต่หากจะนำไปสร้าง AMI ต่อไม่จำเป็นต้อง reboot **หาก reboot ไปแล้วก่อนนำไปสร้าง AMI ให้แน่ใจว่าลบไฟล์ DB ทิ้ง (/etc/tlmvpn/[chap-secret, ipsec.secret]) และ kill process ของ Server แล้ว เพราะไม่งั้นตัวใหม่จะไม่ sync ข้อมูลกับ Database**

**3. หลังจากติดตั้งทั้งหมดเสร็จสิ้นทำการสร้าง image ami**

**4. สร้าง launch template หรือ launch configuration**

**5. สร้าง auto scaling เท่านี้ก็ได้ระบบ vpn server ที่สามารถเพิ่มลดจำนวน instance ได้แล้ว**

---

## VPN Client Installation (ubuntu on-premise)

ผู้ใช้ต้องรันใน mode root ด้วยคำสั่ง `sudo su` ก่อนจะลงโปรแกรม

```sh
curl -L -0 "https://git.io/JP015" -o "tlmvpnClient.zip"
unzip tlmvpnClient.zip
sudo bash tlmvpnClientInstall.sh
```

ตั้ง credential ของ aws cli ในไฟล์ tlmvpnClientStarter.sh ด้วยคำสั่ง `nano /etc/tlmvpn/tlmvpnClientStarter.sh` ก่อนต้องแก้ตัวแปรดังต่อไปนี้ (แต่หากใช้ iam role ให้ทำคล้ายกับ vpn server)
- region
- aws_access_key_id
- aws_secret_access_key
- aws_session_token

พิมพ์คำสั่ง `nano /etc/sysctl.conf` แล้วนำคอมเม้นตรงนี้ออก `net.ipv4.ip_forward=1`

ไปที่ ec2 > vpn client ec2 > action > networking > Change source / destination check > ติํก Stop
หรือทำใน cli ด้วยคำสั่ง `aws ec2 modify-instance-attribute --instance-id=i-xxxรหัสxxx --no-source-dest-check`

เปิดใช้งาน tlmvpn client ด้วยคำสั่งต่อไปนี้

```sh
bash tlmvpnClient.sh -u "username" -p "password" -k "pre-shared-key"
bash tlmvpnClient.sh -m start
```

---

## Optional

### OSPF Route

รัน ospfd บน AWS Linux only (VPN Server)
```sh
sudo service ospfd start
```

รัน ospfd บน Ubuntu (VPN Client)
```sh
sudo systemctl start ospfd
```

### Startup Execuable

หากต้องการให้ VPN Client ทำงานเมื่อ reboot ทุกครั้งให้ config ที่ไฟล์ /etc/rc.local
```sh
#!/bin/bash

sudo /etc/tlmvpn/tlmvpnClient.sh -m restart
sudo systemctl restart ospfd
```

และต้องรันคำสั่งต่อไปนี้เพื่อให้ execute ตอน reboot ได้
```sh
chmod a+x /etc/rc.local
chmod a+x /etc/tlmvpn/tlmvpnClient.sh
chmod a+x /etc/tlmvpn/tlmvpnClientStarter.sh
```
