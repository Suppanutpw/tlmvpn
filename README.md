# TLMVPN
## _Manual AWS Transit Gateway_
[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)

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

ทำการ reboot เครื่อง 1 รอบหลังจากนั้นสามารถใช้ระบบได้ตามปกติโดยไม่ต้องมีคำสั่งเพิ่มเติม และสามารถนำไปสร้าง AMI ต่อได้ **แต่ก่อนนำไปสร้าง AMI ให้แน่ใจว่าลบไฟล์ DB ทิ้ง (/etc/tlmvpn/[chap-secret, ipsec.secret]) และ kill process ของ Server แล้ว เพราะไม่งั้นตัวใหม่จะไม่ sync ข้อมูลกับ Database**

**3. หลังจากติดตั้งทั้งหมดเสร็จสิ้นทำการสร้าง image ami**

**4. สร้าง template configuration อย่าลืมให้ public ip ที่ interface

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

รัน ospfd บน AWS Linux only (VPN Server)
```sh
sudo service ospfd start
```

รัน ospfd บน Ubuntu (VPN Client)
```sh
sudo systemctl start ospfd
```

การตั้งค่า route สำหรับ host ที่ต่อพ่วง VPN Client บน ubuntu โดยพิมพ์คำสั่ง `nano /etc/netplan/50-cloud-init.yaml`
```
network:
    ethernets:
        ens3:
            dhcp4: true
            dhcp6: false
            match:
                macaddress: 0e:0f:14:ec:28:a1
            set-name: ens3
            gateway4: 10.30.1.10 # เพิ่มตรงนี้
            routes:
            - to: 10.20.0.0/16
              via: 10.30.1.10
            - to: 172.16.0.0/16
              via: 10.30.1.10
    version: 2
```
ทำการ reset ระบบ network ด้วยคำสั่งนี้
```sh
sudo netplan apply
```
