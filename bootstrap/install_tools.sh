#!/bin/bash

cd "$(dirname "$0")"/..

modules=(
    starter
    splash
    hostrename
    audioselect
    extendfs
    network-tools
    usbautomount
    rorw
    synczinc
    webconf
    webfiles
    bluetooth-pi
    rtpmidi
    camera-server
    3615-disco
    kiosk
)

for i in "${modules[@]}"; do
    echo
    read -p "Install: $i ... (y/N) ?" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        cd "/opt/Pi-tools/$i"
        ./install.sh
    fi
done


# Regie
cd /opt
git clone https://github.com/KomplexKapharnaum/RPi-Regie.git
cd RPi-Regie
# mr register

# HPlayer2
cd /opt
git clone https://github.com/Hemisphere-Project/HPlayer2.git
cd HPlayer2
# mr register
# ./install.sh
