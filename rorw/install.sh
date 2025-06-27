#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

ln -sf "$BASEPATH/ro" /usr/local/bin/
ln -sf "$BASEPATH/rw" /usr/local/bin/


### randomness
###

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    apt -y install haveged 
## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    pacman -S haveged --noconfirm --needed
fi
systemctl disable systemd-random-seed
systemctl enable haveged
systemctl start haveged

## disable swap
swapoff -a


#
# read only
#

# Detect RAM size to set tmpfs size
RAMSIZE=$(grep MemTotal /proc/meminfo | awk -F ' ' '{print $2}')
if [ -z "$RAMSIZE" ]
then
      RAMSIZE=1024000
fi
TMPSIZE=$(($RAMSIZE/8000))
if [ "$TMPSIZE" -eq "0" ]; then
   TMPSIZE=128
fi
# max TMPSIZE is 1024MB
if [ "$TMPSIZE" -gt "1024" ]; then
   TMPSIZE=1024
fi

EXTRA_fstab=
TARGET_boot=/boot/efi

# ARCH/RASPBIAN Raspberry Pi
if (lsblk -o uuid /dev/mmcblk0p3 > /dev/null 2>&1); then
    UUID_boot=`lsblk -o uuid /dev/mmcblk0p1 | tail -1`
    UUID_root=`lsblk -o uuid /dev/mmcblk0p2 | tail -1`
    UUID_data=`lsblk -o uuid /dev/mmcblk0p3 | tail -1`

    EXTRA_fstab="proc                                   /proc                proc    defaults          0       0"

    if [ -f /boot/firmware/cmdline.txt ]; then
        TARGET_boot=/boot/firmware
        sed -i 's/rootwait/rootwait fastboot noswap ro/g' /boot/firmware/cmdline.txt
        sed -i "s/root=[^ ]*/root=UUID=$UUID_root/g" /boot/firmware/cmdline.txt
    else
        TARGET_boot=/boot
        sed -i 's/rw//g' /boot/cmdline.txt
        sed -i 's/rootwait/rootwait fastboot noswap ro/g' /boot/cmdline.txt
        sed -i "s/root=[^ ]*/root=UUID=$UUID_root/g" /boot/cmdline.txt
    fi 

#XBIAN ayufan RockPro64 eMMc
elif (lsblk -o uuid /dev/mmcblk1p8 > /dev/null 2>&1); then
    UUID_boot=`lsblk -o uuid /dev/mmcblk1p6 | tail -1`
    UUID_root=`lsblk -o uuid /dev/mmcblk1p7 | tail -1`
    UUID_data=`lsblk -o uuid /dev/mmcblk1p8 | tail -1`

    sed -i 's/rw/fastboot noswap ro/g' /boot/extlinux/extlinux.conf
    sed -i "s/root=LABEL=linux-root/root=UUID=$UUID_root/g" /boot/extlinux/extlinux.conf

#XBIAN x86
elif (lsblk -o uuid /dev/sda3 > /dev/null 2>&1); then
    UUID_boot=`lsblk -o uuid /dev/sda1 | tail -1`
    UUID_root=`lsblk -o uuid /dev/sda2 | tail -1`
    UUID_data=`lsblk -o uuid /dev/sda3 | tail -1`

#XBIAN x86 mini
elif (lsblk -o uuid /dev/nvme0n1 > /dev/null 2>&1); then
    UUID_boot=`lsblk -o uuid /dev/nvme0n1p1 | tail -1`
    UUID_root=`lsblk -o uuid /dev/nvme0n1p2 | tail -1`
    UUID_data=`lsblk -o uuid /dev/nvme0n1p3 | tail -1`

else
    echo ""
    echo "Can't find third partition or detect partition system..."
    echo "RORW install FAILED"
    echo ""
    exit 1
fi

# Prepare directories
#
mkdir -p /data
mount -U "$UUID_data" /data
mkdir -p /data/media
mkdir -p /data/var/NetworkManager
mkdir -p /data/var/dnsmasq
mkdir -p /var/lib/dnsmasq
mkdir -p /data/var/tmp

echo "
UUID=$UUID_boot                                 ${TARGET_boot}  vfat    defaults,ro,errors=remount-ro,umask=177        0       0
UUID=$UUID_root                                 /               ext4    defaults,ro,errors=remount-ro                  0       0
UUID=$UUID_data                                 /data           ext4    defaults                                       0       0

tmpfs                                           /tmp            tmpfs   defaults,size=${TMPSIZE}M,mode=1777 0 0
/run                                            /var/run        none    defaults,bind                                  0 0
/tmp                                            /var/lock       none    defaults,bind                                  0 0
/tmp                                            /var/spool      none    defaults,bind                                  0 0
/tmp                                            /var/log        none    defaults,bind                                  0 0
/tmp                                            /var/tmp        none    defaults,bind                                  0 0

/data/var/dnsmasq                               /var/lib/dnsmasq none   defaults,bind                                 0 0
/data/var/NetworkManager                        /var/lib/NetworkManager none defaults,bind                             0 0
" > /etc/fstab

# If snapd is installed, add snap mounts
if [ -d /var/lib/snapd ]; then
    mkdir -p /data/var/snapd
    echo "/data/var/snapd /var/lib/snapd none defaults,bind 0 0" >> /etc/fstab
fi


# add EXTRA_fstab to fstab
if [ -n "$EXTRA_fstab" ]; then
    echo "$EXTRA_fstab" >> /etc/fstab
fi

# apply new fstab
systemctl daemon-reload
mount -a
chmod -R 777 /tmp

# bash prompt color
#
echo "source $BASEPATH/rorw.bashrc" >> /root/.bashrc
echo "OSH_THEME=\"rorw/rorw\"" >> /root/.bashrc


#
# symlink
#

# Oh-my-bash
if [ -d /root/.oh-my-bash ]; then
    mkdir -p /data/var/ohmybash
    mv /root/.oh-my-bash/log /data/var/ohmybash/log
    ln -sf /data/var/ohmybash/log /root/.oh-my-bash/log
fi

# Tailscale (if /var/lib/tailscale exists)
# if [ -d /var/lib/tailscale ]; then
#     mkdir -p /data/var/tailscale
#     mv /var/lib/tailscale /data/var/tailscale
#     ln -sf /data/var/tailscale /var/lib/tailscale
# fi
# TODO: mount with fstab !

#
# fake-hwclock
#

systemctl disable systemd-timesyncd
systemctl disable ntp

ln -sf "$BASEPATH/fake-clock" /usr/local/bin/
ln -sf "$BASEPATH/fake-clock.service" /etc/systemd/system/
ln -sf "$BASEPATH/fake-clock-autosave.service" /etc/systemd/system/
ln -sf "$BASEPATH/fake-clock-autosave.timer" /etc/systemd/system/

systemctl daemon-reload
systemctl enable fake-clock 
systemctl enable fake-clock-autosave.timer

fake-clock save

echo "rw
history -a
ro
fake-clock save
" >> /etc/bash.bash_logout
