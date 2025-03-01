#!/bin/bash

#
#   :: Rasta 7 :: aarch64 :: xbian :: 31/05/2024
#

### Burn image from raspbery pi official website (64bit current version)
### https://www.raspberrypi.com/software/operating-systems/

### Boot with a keyboard and a screen
### login: pi
### password: pi

### Start raspi-config
###
sudo raspi-config

### 3. Interface Options
### I1 SSH  => Enable

### 5. Localisation 
### L2 Timezone => Paris
### L3 Keyboard => France

### 6. Advanced Options
### A2 Network Interface Names => Enable predictable names
### A6 Wayland => Select X11

### Finnish => Reboot

### SSH from remote
#ssh pi@<ip>

### log in as root
###
sudo su root         # =>  root


### Update
###
apt update
apt upgrade


### Change passwords
###
echo "root:rootpi" | chpasswd
echo "pi:pi" | chpasswd


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
apt -y install git wget imagemagick htop build-essential
apt -y install python3 python3-pip python3-setuptools python3-wheel python3-rpi.gpio


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
systemctl stop systemd-networkd
systemctl disable systemd-networkd

rm /etc/resolv.conf
echo "nameserver 1.1.1.1
nameserver 1.0.0.1" > /etc/resolv.conf

echo "rasta-00" > /etc/hostname

echo " [main]
plugins=keyfile
dns=none" > /etc/NetworkManager/NetworkManager.conf

mkdir -p /etc/dnsmasq.d/
systemctl enable dnsmasq
systemctl start dnsmasq


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
sed -i 's/rootwait/rootwait net.ifnames=0/g' /boot/firmware/cmdline.txt

### blackboot
###
systemctl disable getty@tty1
sed -i '$ s/tty1/tty3/' /boot/firmware/cmdline.txt
sed -i 's/rootwait/rootwait logo.nologo consoleblank=0 quiet loglevel=3 vga=current vt.global_cursor_default=0/g' /boot/firmware/cmdline.txt
echo "setterm -cursor on" >> /root/.bashrc

### touch fix (iiyama)
sed -i '$ s/rootwait/rootwait usbhid.mousepoll=0/' /boot/firmware/cmdline.txt

### i2c
###
echo "i2c-dev" >> /etc/modules-load.d/raspberrypi.conf

### oh-my-bash
###
bash -c "$(wget https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh -O -)"

### version
###
echo "7.1  --  bootstraped from https://github.com/Hemisphere-Project/Pi-tools/blob/main/bootstrap/bootstrap-raspbian-pi4.sh" > /boot/VERSION

## write config.txt
## (check if there is no new config.txt settings that you should keep)
##
cp /boot/firmware/config.txt /boot/firmware/config.txt.origin
echo "
#
# Hardware ovelrays
#
dtparam=audio=on        
dtparam=i2c_arm=on
#dtparam=i2s=on
#dtparam=spi=on

#
# Global settings
#
arm_64bit=1
arm_boost=1
force_turbo=1
camera_auto_detect=1
display_auto_detect=1
auto_initramfs=1

#
# FastBoot
#
boot_delay=0
#dtoverlay=sdtweak,overclock_50=100  # Overclock the SD Card from 50 to 100MHz / This can only be done with at least a UHS Class 1 card, might be unstable
disable_splash=1

#
# GPU
#
# Enable DRM VC4 V3D driver
dtoverlay=vc4-kms-v3d
max_framebuffers=2
disable_fw_kms_setup=1
disable_overscan=1

# Resolution
video=HDMI-A-1:1920x1080M@30

[pi3]
gpu_mem=200

[pi4]
gpu_mem=400

[all]
#dwc_otg.speed=1 #legacy USB1.1

" > /boot/firmware/config.txt


## Pi-tools
cd /opt
git clone https://github.com/Hemisphere-Project/Pi-tools.git

# Deploy modules
cd /opt/Pi-tools
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
    # webfiles
    bluetooth-pi
    rtpmidi
    # camera-server
    3615-disco
)
for i in "${modules[@]}"; do
    cd "$i"
    ./install.sh
    cd /opt/Pi-tools
done

# HPlayer2
cd /opt
git clone https://github.com/Hemisphere-Project/HPlayer2.git
cd HPlayer2
./install.sh

# Regie
# cd /opt
# git clone https://github.com/KomplexKapharnaum/RPi-Regie.git
# cd RPi-Regie

