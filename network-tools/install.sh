#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"

cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
echo 'listen-address=10.0.0.1                             
dhcp-range=10.0.0.2,10.0.0.99,255.255.255.0,12h

listen-address=10.1.0.1
dhcp-range=10.1.0.2,10.1.0.99,255.255.255.0,12h

dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases
' > /etc/dnsmasq.conf

mkdir -p /boot/wifi
cp -r "$BASEPATH"/profiles/* /boot/wifi/

ln -sf "$BASEPATH/setnet.service" /etc/systemd/system/
ln -sf "$BASEPATH/setnet" /usr/local/bin/

ln -sf "$BASEPATH/enforce-ipv4@.service" /etc/systemd/system/
ln -sf "$BASEPATH/enforce-ipv4" /usr/local/bin/

ln -sf "$BASEPATH/uplink-fwd@.service" /etc/systemd/system/
ln -sf "$BASEPATH/uplink-fwd" /usr/local/bin/

ln -sf "$BASEPATH/enforce-ping@.service" /etc/systemd/system/
ln -sf "$BASEPATH/enforce-ping" /usr/local/bin/

ln -sf "$BASEPATH/iface-off@.service" /etc/systemd/system/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [network-tools] various network utilities
# setnet                        # set NetworkManager profile from /boot/wifi
# uplink-fwd@wlan0              # set interface as uplink and forward to other interfaces
# enforce-ping@2.0.0.1/wlan0    # ping <test-ip>, restart <iface> if failed
# enforce-ipv4@eth0             # check that ipv4 has been properly set (usefull with late-join antenna)
# iface-off@60/wlan0            # turn-off interface after <min> minutes
" >> /boot/starter.txt
fi

