#!/bin/bash

#
#   :: Rasta 7 :: armv7l :: arch :: 15/09/2020
#


### log in as root
###
su root         # =>  root


### Init Pacman & update
###
pacman-key --init
pacman-key --populate archlinuxarm
rm /etc/ssl/certs/ca-certificates.crt 
pacman -Syu --noconfirm
pacman-db-upgrade
pacman -Sc --noconfirm
ln -sf /etc/ca-certificates/extracted/ca-bundle.trust.crt /etc/ssl/certs/ca-certificates.crt


### Change passwords
###
echo "root:rootpi" | chpasswd
echo "alarm:pi" | chpasswd


### Add alarm to sudoer
###
pacman -S sudo --noconfirm
echo 'alarm ALL=(ALL) NOPASSWD: ALL' | EDITOR='tee -a' visudo


### enable SSH root login
###
sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin/PermitRootLogin/g" /etc/ssh/sshd_config


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
pacman -S python python-pip python-setuptools python-wheel git wget imagemagick htop base-devel --noconfirm --needed


### pikaur
###
cd /opt
git clone https://aur.archlinux.org/pikaur.git
chmod 777 -R pikaur/
cd pikaur
sudo -u alarm makepkg -fsri --noconfirm
rm -Rf pikaur


### Pi Kernel
###
pacman -S linux-rpi --noconfirm

### RPi.GPIO
###
# pikaur -S python-raspberry-gpio --noconfirm
pip install RPi.GPIO


### mosquitto server
###
pacman -S mosquitto --noconfirm --needed


### avahi
###
pacman -S avahi nss-mdns  --noconfirm --needed
sed -i 's/use-ipv6=yes/use-ipv6=no/g' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon
systemctl start avahi-daemon

### randomness
###
pacman -S haveged --noconfirm --needed
systemctl enable haveged
systemctl start haveged

### switch from netctl/networkd to NetworkManager
###
pacman -S networkmanager dnsmasq --noconfirm --needed
pacman -R dhcpcd --noconfirm
pacman -R netctl --noconfirm
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl stop systemd-networkd
systemctl disable systemd-networkd

rm /etc/resolv.conf
echo "nameserver 8.8.8.8
nameserver 1.1.1.1" > /etc/resolv.conf

echo "hberry" > /etc/hostname

echo " [main]
plugins=keyfile
dns=none" > /etc/NetworkManager/NetworkManager.conf

mkdir -p /etc/dnsmasq.d/
systemctl enable dnsmasq
systemctl start dnsmasq
systemctl enable NetworkManager
systemctl start NetworkManager
nmcli con add type ethernet con-name eth0-dhcp ifname eth0


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
sed -i '$ s/$/ net.ifnames=0/' /boot/cmdline.txt

### french keyboard
###
echo "loadkeys fr" >> /etc/bash.bashrc

### i2c
###
echo "i2c-dev" >> /etc/modules-load.d/raspberrypi.conf

### blackboot
###
systemctl disable getty@tty1
systemctl disable getty@tty3
sed -i '$ s/tty1/tty3/' /etc/systemd/system/getty.target.wants/getty@tty3.service
sed -i '$ s/tty1/tty3/' /boot/cmdline.txt
sed -i '$ s/$/ logo.nologo vt.global_cursor_default=0 consoleblank=0 quiet loglevel=1 vga=current/' /boot/cmdline.txt

### version
###
echo "7.0  --  bootstraped from https://framagit.org/KXKM/rasta-os" > /boot/VERSION

### write config.txt
### (check if there is no new config.txt settings that you should keep)
###
cp /boot/config.txt /boot/config.txt.origin
echo "

##
## HBERRY settings
##
initramfs initramfs-linux.img followkernel

#
# GPU 
# See https://www.raspberrypi.org/documentation/configuration/config-txt/video.md
#
gpu_mem=200
dtoverlay=vc4-kms-v3d
max_framebuffers=2

#
# VIDEO 
# See https://www.raspberrypi.org/documentation/configuration/config-txt/video.md
#
hdmi_force_hotplug=1    # Force HDMI (even without cable)
hdmi_drive=2            # 1: DVI mode / 2: HDMI mode
hdmi_group=2            # 0: autodetect / 1: CEA (TVs) / 2: DMT (PC Monitor)
hdmi_mode=82            # 82: 1080p / 85: 720p / 16: 1024x768 / 51: 1600x1200 / 9: 800x600

#
# Audio
#
dtparam=audio=on
audio_pwm_mode=2

#
# I2C
#
dtparam=i2c_arm=on
dtparam=i2c1=on

#
# USB
#
#dwc_otg.speed=1 #legacy USB1.1

#
# Display
#
# dtoverlay=i2c-gpio,i2c_gpio_sda=15,i2c_gpio_scl=14  ## I2C (small 35 TFT touchscreen ?)
# dtoverlay=tft35a:rotate=90  # GPIO 3.5TFT screen
# display_lcd_rotate=2        # Onboard display

#
# FastBoot
#
initial_turbo=30
boot_delay=0
disable_splash=1                        # Disable the rainbow splash screen
# dtoverlay=sdtweak,overclock_50=100    # Overclock the SD Card from 50 to 100MHz / This can only be done with at least a UHS Class 1 card

#
# Camera module
#
# start_file=start_x.elf
# fixup_file=fixup_x.dat



" > /boot/config.txt


## MyRepos
# cd /opt
# git clone git://myrepos.branchable.com/ myrepos
# cp /opt/myrepos/mr /usr/local/bin/
# rm -Rf myrepos

# Deploy modules
cd /opt
git clone https://github.com/Hemisphere-Project/Pi-tools.git
cd Pi-tools

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
    bluetooth-pi
    rtpmidi
    camera-server
    3615-disco
)

for i in "${modules[@]}"; do
    cd "$i"
    ./install.sh
    cd /opt/Pi-tools
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
./install.sh



