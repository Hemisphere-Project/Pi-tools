# Rasta-OS

Bootstrap a fresh ArchARM image for RaspberryPi with rasta-modules


### Create Arch image
- Create image using instructions here: https://archlinuxarm.org/platforms/armv7/broadcom/raspberry-pi-2
- ADD 3rd partition (ext4) using fdisk or gparted

### Bootstrap image
- Plug ethernet cable
- Boot the Pi with the fresh image
- ssh into it, or use keyboard and screen (user: alarm / password: alarm)
- `cd /opt && git clone https://framagit.org/KXKM/rasta-os.git && cd rasta-os`
- `./bootstrap.sh`
  
