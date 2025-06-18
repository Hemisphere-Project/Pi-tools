# install Ubuntu server with OpenSSH enabled 
# User : hberry // pi

# Remote login as hberry
sudo su root         # =>  root

# Upgrade no confirm
apt update
apt upgrade -y
apt dist-upgrade -y

# Change passwords
echo "root:rootpi" | chpasswd

# Enable SSH root login
sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin/PermitRootLogin/g" /etc/ssh/sshd_config
sed -i "s/UsePAM yes/UsePAM no/g" /etc/ssh/sshd_config
echo "IPQoS 0x00" >> /etc/ssh/ssh_config
echo "IPQoS 0x00" >> /etc/ssh/sshd_config
echo "IPQoS cs0 cs0" >> /etc/ssh/sshd_config

# Allow PasswordAuthentication
sed -i "s/PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/#PasswordAuthentication yes/PasswordAuthentication yes/g" /etc/ssh/sshd_config
rm /etc/ssh/sshd_config.d/50-cloud-init.conf

# Generate root ssh keys
cd /root
cat /dev/zero | ssh-keygen -q -N ""      # => no password

# Restart ssh
systemctl restart ssh
# [from remote machine] ssh-copy-id root@<IP-ADDRESS>

### oh-my-bash
###
grep -qxF 'DISABLE_UPDATE_PROMPT=true' ~/.bashrc || echo 'DISABLE_UPDATE_PROMPT=true' >> ~/.bashrc
grep -qxF 'DISABLE_AUTO_UPDATE=true' ~/.bashrc || echo 'DISABLE_AUTO_UPDATE=true' >> ~/.bashrc
bash -c "$(wget https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh -O -)"

# Disable wait for network
systemctl stop iscsid.socket
systemctl disable iscsid.socket
systemctl disable --now iscsid.service
systemctl disable --now open-iscsi.service
systemctl disable --now systemd-networkd-wait-online.service
systemctl disable --now unattended-upgrades.service

# Python & tools
apt -y install git wget tmux imagemagick htop libsensors5 build-essential lsof nano
apt -y install python3 python3-pip python3-setuptools python3-wheel pipx pipenv

# Mosquitto server
apt -y install mosquitto
systemctl disable mosquitto

# Avahi / mdns
apt -y install avahi-daemon avahi-utils libnss-mdns
sed -i 's/use-ipv6=yes/use-ipv6=no/g' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon
systemctl start avahi-daemon

### randomness
###
apt -y install haveged 
systemctl enable haveged
systemctl start haveged

# switch from netctl/networkd to NetworkManager
apt -y install network-manager dnsmasq

### switch from netplan/networkd to NetworkManager/dnsmasq
###
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl stop systemd-networkd
systemctl disable systemd-networkd

rm /etc/resolv.conf
echo "nameserver 1.1.1.1
nameserver 1.0.0.1" > /etc/resolv.conf

echo "[main]
plugins=keyfile
dns=none

[connection]
wifi.powersave = 2

[keyfile]
unmanaged-devices=interface-name:p2p-dev-*
" > /etc/NetworkManager/NetworkManager.conf

mkdir -p /etc/dnsmasq.d/
systemctl enable dnsmasq
systemctl start dnsmasq

rm /etc/netplan/*.yaml
cat << EOF > /etc/netplan/01-netcfg.yaml
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 /etc/netplan/01-netcfg.yaml

netplan generate
netplan apply
systemctl enable NetworkManager.service
systemctl restart NetworkManager.service
systemctl disable NetworkManager-wait-online.service

# Disable IPv6
echo '# Disable IPv6
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
net.ipv6.conf.enp1s0.disable_ipv6=1
net.ipv6.conf.enp2s0.disable_ipv6=1
net.ipv6.conf.eth0.disable_ipv6=1
net.ipv6.conf.eth1.disable_ipv6=1
net.ipv6.conf.wint.disable_ipv6=1
net.ipv6.conf.wlan0.disable_ipv6=1
net.ipv6.conf.wlan1.disable_ipv6=1' > /etc/sysctl.d/40-ipv6.conf

# Network intrface name
sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/g' /etc/default/grub
update-grub

# Internal wifi as wint
echo 'ACTION=="add", SUBSYSTEM=="net", DRIVERS=="iwlwifi", NAME="wint"' > /etc/udev/rules.d/72-static-name.rules

# Plymouth spinner
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash consoleblank=0 loglevel=0 fbcon=nodefer vt.global_cursor_default=0 consoleblank=0 rd.systemd.show_status=auto rd.udev.log-priority=3"/g' /etc/default/grub
sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=0\nGRUB_RECORDFAIL_TIMEOUT=$GRUB_TIMEOUT/g' /etc/default/grub   # prevent grub from displaying once read-only system
update-grub
apt -y install plymouth-theme-spinner
sed -i 's/UseFirmwareBackground=true/UseFirmwareBackground=false/g' /usr/share/plymouth/themes/default.plymouth
mv /usr/share/plymouth/themes/spinner/watermark.png /usr/share/plymouth/themes/spinner/watermark.png.bak

# Note: putting console=ttyS0 in GRUB_CMDLINE_LINUX= removes all messages but also hides Plymouth spinner

# Black getty
mkdir -p /etc/systemd/system/getty@tty1.service.d/
echo '[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --skip-login --nonewline --noissue --autologin root --noclear %I $TERM' > /etc/systemd/system/getty@tty1.service.d/skip-prompt.conf
systemctl daemon-reload



### version
###
echo "9.0  --  bootstraped with https://github.com/Hemisphere-Project/Pi-tools" > /boot/VERSION

# Clean up
rm /var/lib/man-db/auto-update
systemctl mask apt-daily-upgrade
systemctl mask apt-daily
systemctl disable apt-daily-upgrade.timer
systemctl disable apt-daily.timer
apt autoremove --purge -y

## Pi-tools
cd /opt
git clone https://github.com/Hemisphere-Project/Pi-tools.git

# Deploy modules
cd /opt/Pi-tools
modules=(
    starter         #+ ok 
    hostrename      #+ ok
    network-tools   #+ ok
    rorw            # ok
    usbautomount    #+ ok
    extendfs        # ok
    synczinc        ## todo  
    webconf         ## flask broken.. 
    # webfiles      ## todo  
    rtpmidi         ## todo
    # 3615-disco    ## flask broken.. 
)
for i in "${modules[@]}"; do
    cd "$i"
    ./install.sh
    cd /opt/Pi-tools
done

# MPV
apt -y install mpv ffmpeg intel-gpu-tools libvdpau-va-gl1 intel-media-va-driver-non-free 

# HPlayer2
cd /opt
git clone https://github.com/Hemisphere-Project/HPlayer2.git
cd HPlayer2
./install.sh

