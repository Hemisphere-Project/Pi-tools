#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

# NOTE: the ro/rw/with_rw toggle symlinks are created at the very END of this
# script, only once the install has fully succeeded. is_module_installed keys on
# them, so creating them up-front would make a machine that FAILED partition
# detection report "already installed" while its root is still fully writable.


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
IS_X86=

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
    IS_X86=1

#XBIAN x86 mini (NVMe) — probe the 3rd PARTITION, not the whole disk, or any
# NVMe machine without the 3-partition layout matches and UUID_data comes back
# empty (-> "UUID=  /data" -> unbootable).
elif (lsblk -o uuid /dev/nvme0n1p3 > /dev/null 2>&1); then
    UUID_boot=`lsblk -o uuid /dev/nvme0n1p1 | tail -1`
    UUID_root=`lsblk -o uuid /dev/nvme0n1p2 | tail -1`
    UUID_data=`lsblk -o uuid /dev/nvme0n1p3 | tail -1`
    IS_X86=1

else
    echo ""
    echo "Can't find third partition or detect partition system..."
    echo "RORW install FAILED"
    echo ""
    exit 1
fi

# Never write fstab with a missing UUID — a blank /data UUID drops the machine
# into emergency mode on the next boot.
if [ -z "$UUID_boot" ] || [ -z "$UUID_root" ] || [ -z "$UUID_data" ]; then
    echo ""
    echo "RORW: could not read all partition UUIDs (boot='$UUID_boot' root='$UUID_root' data='$UUID_data')"
    echo "RORW install FAILED — fstab left untouched"
    echo ""
    exit 1
fi

# Prepare directories
#
mkdir -p /data
if ! mountpoint -q /data; then
    if ! mount -U "$UUID_data" /data; then
        echo "RORW: cannot mount data partition ($UUID_data) — FAILED"
        exit 1
    fi
fi
# (only now that /data is really mounted do we create its skeleton, so it never
#  lands on the root filesystem and gets shadowed when /data mounts for real)
mkdir -p /data/media
mkdir -p /data/var/NetworkManager
mkdir -p /data/var/dnsmasq
mkdir -p /var/lib/dnsmasq
mkdir -p /data/var/tmp
mkdir -p /data/var/cache
mkdir -p /root/.cache

# /data and every bind sourced from it carry `nofail`, so a corrupt or missing
# /data (hard power cut on an unattended box) boots degraded instead of dropping
# to an emergency shell. /data also gets a fsck pass order (2).
echo "
UUID=$UUID_boot                                 ${TARGET_boot}  vfat    defaults,ro,errors=remount-ro,umask=177        0       0
UUID=$UUID_root                                 /               ext4    defaults,ro,errors=remount-ro                  0       0
UUID=$UUID_data                                 /data           ext4    defaults,nofail,x-systemd.device-timeout=10s   0       2

tmpfs                                           /tmp            tmpfs   defaults,size=${TMPSIZE}M,mode=1777 0 0
/run                                            /var/run        none    defaults,bind                                  0 0
/tmp                                            /var/lock       none    defaults,bind                                  0 0
/tmp                                            /var/spool      none    defaults,bind                                  0 0
/tmp                                            /var/log        none    defaults,bind                                  0 0
/tmp                                            /var/tmp        none    defaults,bind                                  0 0

/data/var/cache                                 /root/.cache       none    defaults,bind,nofail                           0 0
/data/var/dnsmasq                               /var/lib/dnsmasq none   defaults,bind,nofail                          0 0
/data/var/NetworkManager                        /var/lib/NetworkManager none defaults,bind,nofail                      0 0
" > /etc/fstab

# If snapd is installed, persist its state to /data. Seed the persistent copy
# with the existing content FIRST — binding an empty dir over /var/lib/snapd
# wipes the seeded snaps and breaks snapd after reboot (Ubuntu ships it seeded).
if [ -d /var/lib/snapd ]; then
    mkdir -p /data/var/snapd
    cp -a /var/lib/snapd/. /data/var/snapd/ 2>/dev/null
    echo "/data/var/snapd /var/lib/snapd none defaults,bind,nofail 0 0" >> /etc/fstab
fi


# add EXTRA_fstab to fstab
if [ -n "$EXTRA_fstab" ]; then
    echo "$EXTRA_fstab" >> /etc/fstab
fi

# x86/GRUB: neutralize recordfail, or the first unclean boot makes GRUB wait at
# its menu forever (timeout -1) — a headless box hangs before it ever boots.
if [ -n "$IS_X86" ] && [ -f /etc/default/grub ]; then
    if grep -q '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub; then
        sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=2/' /etc/default/grub
    else
        echo 'GRUB_RECORDFAIL_TIMEOUT=2' >> /etc/default/grub
    fi
    update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null
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

echo 'if [ "$(id -u)" -eq 0 ]; then
rw
history -a
ro
fake-clock save
fi
' >> /etc/bash.bash_logout


#
# install succeeded — publish the toggle symlinks last, so is_module_installed
# only sees rorw as "installed" once the whole thing actually ran.
#
ln -sf "$BASEPATH/ro" /usr/local/bin/
ln -sf "$BASEPATH/rw" /usr/local/bin/
mkdir -p /usr/local/lib/pitools
ln -sf "$BASEPATH/with_rw.sh" /usr/local/lib/pitools/
