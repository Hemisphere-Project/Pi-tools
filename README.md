# Pi-tools
Tools for embedded

## Bootstrap
Bootstrap a fresh image for RaspberryPi with tools

### Create Manjaro image
- Create image using ManjaroARM for Pi4 (Pi3 compatible) with Etcher 
- IMPORTANT: Once image burned on microSD, add a 3rd partition (ext4) using fdisk or gparted on the microSD

### Create Raspbian image
- download official RaspiOS minimal (no desktop) and burn it using etcher
- IMPORTANT: add a 3rd partition (ext4) using fdisk or gparted

### Bootsrap the image
- Plug ethernet cable
- Boot the Pi with the fresh image
- ssh into it, or use keyboard and screen (MANJARO: pi / pi // RASPBIAN: pi / raspberry)

#### MANJARO
```
sudo su root
pacman -Sy git
cd /opt
git clone https://github.com/Hemisphere-Project/Pi-tools
cd Pi-tools/bootstrap
./bootstrap-manjaro-pi4.sh
./install_tools.sh
```

#### XBIAN
```
sudo su root
apt update && apt install git
cd /opt
git clone https://github.com/Hemisphere-Project/Pi-tools
cd Pi-tools/bootstrap
./bootstrap-xbian-rp64.sh
./install_tools.sh
```

