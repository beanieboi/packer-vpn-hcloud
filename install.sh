#!/bin/bash

set -ex

while [ 1 ]; do
  apt-get update
  if [ $? -eq 0 ]; then
    break
  fi
  sleep 2
done

apt-get upgrade -y

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

apt-get install -y strongswan strongswan-plugin-eap-mschapv2 moreutils iptables-persistent rng-tools
nohup rngd -r /dev/urandom &>/dev/null &
mkdir vpn-certs
ipsec pki --gen --type rsa --size 4096 --outform pem > vpn-certs/server-root-key.pem
chmod 600 vpn-certs/server-root-key.pem
ipsec pki --self --ca --lifetime 3650 --in vpn-certs/server-root-key.pem --type rsa --dn "C=DE, O=VPN Server, CN=VPN Server Root CA" --outform pem > vpn-certs/server-root-ca.pem
ipsec pki --gen --type rsa --size 4096 --outform pem > vpn-certs/vpn-server-key.pem
ipsec pki --pub --in vpn-certs/vpn-server-key.pem --type rsa | ipsec pki --issue --lifetime 1825 --cacert vpn-certs/server-root-ca.pem --cakey vpn-certs/server-root-key.pem --dn "C=US, O=VPN Server, CN=vpn.abwesend.com" --san vpn.abwesend.com --flag serverAuth --flag ikeIntermediate --outform pem > vpn-certs/vpn-server-cert.pem

sudo cp ./vpn-certs/vpn-server-cert.pem /etc/ipsec.d/certs/vpn-server-cert.pem
sudo cp ./vpn-certs/vpn-server-key.pem /etc/ipsec.d/private/vpn-server-key.pem
sudo chown root /etc/ipsec.d/private/vpn-server-key.pem
sudo chgrp root /etc/ipsec.d/private/vpn-server-key.pem
sudo chmod 600 /etc/ipsec.d/private/vpn-server-key.pem
sudo cp /etc/ipsec.conf /etc/ipsec.conf.original
echo '' | sudo tee /etc/ipsec.conf

sudo ufw disable
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F
iptables -Z
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p udp --dport  500 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 4500 -j ACCEPT
sudo iptables -A FORWARD --match policy --pol ipsec --dir in  --proto esp -s 10.10.10.10/24 -j ACCEPT
sudo iptables -A FORWARD --match policy --pol ipsec --dir out --proto esp -d 10.10.10.10/24 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.10.10.10/24 -o eth0 -m policy --pol ipsec --dir out -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.10.10.10/24 -o eth0 -j MASQUERADE
sudo iptables -t mangle -A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.10/24 -o eth0 -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
sudo iptables -A INPUT -j DROP
sudo iptables -A FORWARD -j DROP
sudo netfilter-persistent save
sudo netfilter-persistent reload
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.accept_redirects=0
sudo sysctl -w net.ipv4.conf.all.send_redirects=0
