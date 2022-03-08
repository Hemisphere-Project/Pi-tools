# raspi-filemanager

Web based filemanager

## Install

- pacman -S php
- ln -s /opt/webfiles/webfiles.service /etc/systemd/system/
- mv /opt/webfiles/www/data /data/var/webfiles && ln -s /data/var/webfiles /opt/webfiles/www/data

## Usage

- goto http://hostname.local:9000
- user: admin / pass: adminpi
