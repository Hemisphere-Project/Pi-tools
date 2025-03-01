#!/bin/bash

#
#   :: HBerry 2 :: aarch64 :: manjaro :: 24/06/2024
#

sudo su root         # =>  root

### Init Pacman & update
###
pacman -Syu --noconfirm
pacman-db-upgrade
pacman -Sc --noconfirm


### Change passwords
###
echo "root:rootpi" | chpasswd
echo "pi:pi" | chpasswd


### enable SSH root login
###
sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin/PermitRootLogin/g" /etc/ssh/sshd_config
sed -i "s/UsePAM yes/UsePAM no/g" /etc/ssh/sshd_config
echo "IPQoS 0x00" >> /etc/ssh/ssh_config
echo "IPQoS 0x00" >> /etc/ssh/sshd_config
echo "IPQoS cs0 cs0" >> /etc/ssh/sshd_config

### generate root ssh keys
###
cd /root
cat /dev/zero | ssh-keygen -q -N ""      # => no password

### restart ssh
###
systemctl restart sshd
# [from remote machine] ssh-copy-id root@<IP-ADDRESS>


### python & tools
###
pacman -S python python-pip python-setuptools python-wheel git wget imagemagick htop base-devel atop python-pipenv tmux --noconfirm --needed


### pikaur
###
# cd /opt
# git clone https://aur.archlinux.org/pikaur.git
# chmod 777 -R pikaur/
# cd pikaur
# sudo -u pi makepkg -fsri --noconfirm

### Pi Kernel
###
# pacman -S linux-rpi --noconfirm

### RPi.GPIO
###
# pikaur -S python-raspberry-gpio --noconfirm
# pip install RPi.GPIO --break-system-packages


### mosquitto server
###
pacman -S mosquitto --noconfirm --needed

### Audio Analog
##
# modprobe snd_bcm2835
# echo 'snd_bcm2835'  >>  /etc/modules



### avahi
###
pacman -S avahi nss-mdns  --noconfirm --needed
sed -i 's/use-ipv6=yes/use-ipv6=no/g' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon
systemctl start avahi-daemon



### switch from netctl/networkd to NetworkManager
###
pacman -S networkmanager dnsmasq --noconfirm --needed
pacman -R dhcpcd --noconfirm
pacman -R netctl --noconfirm
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl stop systemd-networkd.socket
systemctl disable systemd-networkd.socket
systemctl stop systemd-networkd
systemctl disable systemd-networkd

rm /etc/resolv.conf
echo "nameserver 8.8.8.8
nameserver 1.1.1.1" > /etc/resolv.conf

echo "hberry-000" > /etc/hostname

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
net.ipv6.conf.wint.disable_ipv6 = 1
net.ipv6.conf.wlan0.disable_ipv6 = 1
net.ipv6.conf.wlan1.disable_ipv6 = 1' > /etc/sysctl.d/40-ipv6.conf

### network interface name persistence (internal will be wint, external will be wlan0, wlan1...)
### 
sed -i '$ s/$/ net.ifnames=0/' /boot/cmdline.txt
echo 'ACTION=="add", SUBSYSTEM=="net", DRIVERS=="brcmfmac", NAME="wint"' > /etc/udev/rules.d/72-static-name.rules

### i2c
###
echo "i2c-dev" >> /etc/modules-load.d/raspberrypi.conf

### blackboot
###
systemctl disable getty@tty1
sed -i '$ s/tty1/tty3/' /boot/cmdline.txt
sed -i '$ s/$/ loglevel=1 vt.global_cursor_default=0/' /boot/cmdline.txt      # logo.nologo vt.global_cursor_default=0 consoleblank=0 quiet vga=current

### touch fix (iiyama)
sed -i '$ s/$/ usbhid.mousepoll=0/' /boot/cmdline.txt

### spinner splash
plymouth-set-default-theme -R spinner

### version
###
echo "8.0  --  bootstraped with https://github.com/Hemisphere-Project/Pi-tools" > /boot/VERSION

### write config.txt
### (check if there is no new config.txt settings that you should keep)
###
cp /boot/config.txt /boot/config.txt.origin
echo "
#
# See /boot/overlays/README for all available options
#

auto_initramfs=1
kernel=kernel8.img
arm_64bit=1
arm_boost=1
disable_overscan=1
dtparam=krnbt=on

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
# AUDIO
#
dtoverlay=pisound    # necessary to get analog jack working on Pi4 !
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
avoid_warnings=1
initial_turbo=30
boot_delay=0
disable_splash=1                        # Disable the rainbow splash screen
disable_poe_fan=1                       # Disable the POE fan
# dtoverlay=sdtweak,overclock_50=100    # Overclock the SD Card from 50 to 100MHz / This can only be done with at least a UHS Class 1 card

" > /boot/config.txt

## Pi-tools
cd /opt
git clone https://github.com/Hemisphere-Project/Pi-tools.git

# Deploy modules
cd /opt/Pi-tools
modules=(
    starter         # ok
    #splash         # not needed on Manjaro (plymouth splash is already installed)
    hostrename      # ok
    network-tools  ## todo
    audioselect    ## todo
    usbautomount    # ok
    rorw           ## todo
    extendfs        # ok
    synczinc       ## todo  
    webconf         ## flask broken.. 
    # webfiles      ## todo  
    bluetooth-pi    # todo  
    rtpmidi         ## todo
    # camera-server
    3615-disco      ## flask broken.. 
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


