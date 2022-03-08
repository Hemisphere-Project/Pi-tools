#!/bin/bash

##
# Change static IP to 2.0.10.ID

for filename in /etc/NetworkManager/system-connections/*; do
    sed -i -e 's/2.0.10.'$1'/2.0.10.254/g' $filename
done

##
# Change hostname

sed -i -e 's/rastapi-'$1'/rastapi-0/g' /boot/config.txt
