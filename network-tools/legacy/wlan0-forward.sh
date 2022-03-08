#!/bin/bash
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE

iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
ip route del 0/0 dev eth0 &> /dev/null

iptables -A FORWARD -i wlan0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan1 -o wlan0 -j ACCEPT
ip route del 0/0 dev wlan1 &> /dev/null

