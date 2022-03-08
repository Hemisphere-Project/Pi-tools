#!/bin/bash

##
# Change static IP to 2.0.10.ID

for filename in /etc/NetworkManager/system-connections/*; do
    sed -i -e 's/2.0.10.254/2.0.10.'$1'/g' $filename
done

##
# Change hostname

sed -i -e 's/rastapi-0/rastapi-'$1'/g' /boot/config.txt
