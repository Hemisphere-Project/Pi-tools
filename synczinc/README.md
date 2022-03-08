# raspi-syncthing

Syncthing wrapper to auto sync /data/sync folder on LAN

## install

- ln -s /opt/synczinc/sync-[master or client].service /etc/systemd/system/
- pip3 install -r requirements.txt
- pacman -S syncthing

## TODO

- test syncmaster on kconfig
- zeroconf special annoucment for SYncMaster
- detect switch from/to master (and reset accordingly)
