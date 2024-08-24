#!/bin/bash

#
#   :: Rasta 7 :: aarch64 :: xbian :: 13/10/2021
#


### log in as root
###
su root         # =>  root


### Init Pacman & update
###
apt update
apt upgrade


### Change passwords
###
echo "root:root64" | chpasswd
echo "rock64:rock64" | chpasswd


### enable SSH root login
###
sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin/PermitRootLogin/g" /etc/ssh/sshd_config
sed -i "s/UsePAM yes/UsePAM no/g" /etc/ssh/sshd_config

### generate root ssh keys
###
cd /root
cat /dev/zero | ssh-keygen -q -N ""      # => no password

### prevent ssh hang
###
echo "IPQoS 0x00" >> /etc/ssh/ssh_config
echo "IPQoS 0x00" >> /etc/ssh/sshd_config

### restart ssh
###
systemctl restart sshd
# [from remote machine] ssh-copy-id root@<IP-ADDRESS>


### python & tools
###
apt -y install python3 python3-pip python3-setuptools python3-wheel
apt -y install git wget imagemagick htop build-essential


### RP64.GPIO
###
########## WARNING GPIO disabled on Ayufan image ?
pip3 install git+https://github.com/Angoosh/RockPro64-RP64.GPIO


### mosquitto server
###
apt -y install mosquitto 


### avahi / mdns
###
apt -y install avahi-daemon libnss-mdns  
sed -i 's/use-ipv6=yes/use-ipv6=no/g' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon
systemctl start avahi-daemon

### randomness
###
apt -y install haveged 
systemctl enable haveged
systemctl start haveged

### switch from netplan/networkd to NetworkManager/dnsmasq
###
apt -y install dnsmasq 
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl stop systemd-networkd
systemctl disable systemd-networkd

rm /etc/resolv.conf
echo "nameserver 1.1.1.1
nameserver 1.0.0.1" > /etc/resolv.conf

echo "rasta64" > /etc/hostname

echo " [main]
plugins=keyfile
dns=none" > /etc/NetworkManager/NetworkManager.conf

mkdir -p /etc/dnsmasq.d/
systemctl enable dnsmasq
systemctl start dnsmasq
nmcli con add type ethernet con-name eth0-dhcp ifname eth0
nmcli con add type ethernet con-name enp1s0-dhcp ifname enp1s0

mv /etc/netplan/eth0.yaml /etc/netplan/eth0.yaml.BAK
cat << EOF > /etc/netplan/01-netcfg.yaml
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: NetworkManager
EOF

netplan generate
netplan apply
systemctl enable NetworkManager.service
systemctl restart NetworkManager.service

nmcli connection delete eth0
nmcli connection delete enp1s0

########## WARNING might need a re-connect to a different IP !


### disable ipv6
###
echo '# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.eth0.disable_ipv6 = 1
net.ipv6.conf.wlan0.disable_ipv6 = 1
net.ipv6.conf.wlan1.disable_ipv6 = 1' > /etc/sysctl.d/40-ipv6.conf

### network interface name persistence
### 
sed -i 's/rootwait/rootwait net.ifnames=0/g' /boot/extlinux/extlinux.conf

### blackboot
###
systemctl disable getty@tty1
sed -i 's/rootwait/rootwait consoleblank=0 quiet loglevel=3 console=tty3 vga=current vt.global_cursor_default=0/g' /boot/extlinux/extlinux.conf
echo "setterm -cursor on" >> /root/.bashrc

### french keyboard
###
echo "loadkeys fr" >> /etc/bash.bashrc

### i2c
###
########## WARNING GPIO disabled on Ayufan image ?
# echo "i2c-dev" >> /etc/modules-load.d/raspberrypi.conf


### blackboot
###
# systemctl disable getty@tty1
# systemctl disable getty@tty3
# sed -i '$ s/tty1/tty3/' /etc/systemd/system/getty.target.wants/getty@tty3.service
# sed -i '$ s/tty1/tty3/' /boot/cmdline.txt
# sed -i '$ s/$/ logo.nologo vt.global_cursor_default=0 consoleblank=0 quiet loglevel=1 vga=current/' /boot/cmdline.txt

### version
###
# echo "7.0  --  bootstraped from https://framagit.org/KXKM/rasta-os" > /boot/VERSION

### write config.txt
### (check if there is no new config.txt settings that you should keep)
###
# cp /boot/config.txt /boot/config.txt.origin
# echo "
# ##
# ## RASPBERRY PI settings
# ##
# gpu_mem=200
# dtparam=audio=on
# audio_pwm_mode=2
# dtparam=i2c_arm=on
# dtparam=i2c1=on
# initramfs initramfs-linux.img followkernel

# #dwc_otg.speed=1 #legacy USB1.1

# #
# # Display
# #
# # dtoverlay=i2c-gpio,i2c_gpio_sda=15,i2c_gpio_scl=14  ## I2C (small 35 TFT touchscreen ?)
# dtoverlay=tft35a:rotate=90  # GPIO 3.5TFT screen
# display_lcd_rotate=2        # Onboard display

# #
# # FastBoot
# #
# boot_delay=0
# #dtoverlay=sdtweak,overclock_50=100  # Overclock the SD Card from 50 to 100MHz / This can only be done with at least a UHS Class 1 card
# disable_splash=1    # Disable the rainbow splash screen

# #
# # Camera module
# #
# #start_file=start_x.elf
# #fixup_file=fixup_x.dat

# #
# # HDMI 
# # See https://www.raspberrypi.org/documentation/configuration/config-txt/video.md
# #
# hdmi_force_hotplug=1    # Force HDMI (even without cable)
# hdmi_drive=2            # 1: DVI mode / 2: HDMI mode
# hdmi_group=2            # 0: autodetect / 1: CEA (TVs) / 2: DMT (PC Monitor)
# hdmi_mode=82            # 82: 1080p / 85: 720p / 16: 1024x768 / 51: 1600x1200 / 9: 800x600

# #
# # Pi4
# #
# #[pi4]
# # Enable DRM VC4 V3D driver on top of the dispmanx display stack
# #dtoverlay=vc4-fkms-v3d
# #max_framebuffers=2


# " > /boot/config.txt


## MyRepos
cd /opt
git clone git://myrepos.branchable.com/ myrepos
cp /opt/myrepos/mr /usr/local/bin/
rm -Rf myrepos

# Deploy modules
cd /opt
modules=(
    starter
    splash
    hostrename
    network-tools
    audioselect
    usbautomount
    rorw
    extendfs
    synczinc
    webconf
    webfiles
    # bluetooth-pi
    rtpmidi
    # camera-server
    3615-disco
)
for i in "${modules[@]}"; do
    git clone https://framagit.org/KXKM/rpi-modules/"$i".git
    cd "$i"
    mr register
    ./install.sh
    cd /opt/
done

# HPlayer2
cd /opt
git clone https://github.com/Hemisphere-Project/HPlayer2.git
cd HPlayer2
mr register
./install.sh

# Regie
# cd /opt
# git clone https://github.com/KomplexKapharnaum/RPi-Regie.git
# cd RPi-Regie
# mr register

