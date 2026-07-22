"""Bootstrap a fresh system for Pi-tools.

Consolidates bootstrap-raspbian-pi4.sh and bootstrap-ubuntu-server-x86.sh
into a single Python-driven bootstrap that auto-detects platform.
"""

import os
import platform as platform_mod
import re
import subprocess

from setup import utils, ui

MARKER = '/opt/Pi-tools/.bootstrapped'


def is_bootstrapped():
    return os.path.isfile(MARKER)


def mark_bootstrapped():
    os.makedirs(os.path.dirname(MARKER), exist_ok=True)
    with open(MARKER, 'w') as f:
        f.write('1\n')


def run_bootstrap(platinfo, cfg):
    """Run full system bootstrap. Skips if already done."""
    if is_bootstrapped():
        ui.skip("System already bootstrapped")
        return

    ui.header("System Bootstrap")

    _update_system()
    _configure_locale()
    _configure_ssh()
    _set_password(cfg)
    _install_base_packages()
    _install_python()
    _install_nodejs()
    _install_uv()
    _install_mosquitto()
    _install_avahi()
    _install_haveged()
    _setup_network_manager(platinfo)
    _disable_ipv6(platinfo)
    _quiet_boot(platinfo)
    _install_ohmybash()

    # Platform-specific
    if platinfo['is_pi']:
        _bootstrap_pi(platinfo, cfg)
    elif platinfo['is_x86']:
        _bootstrap_x86(platinfo)

    # WiFi country
    wifi_country = cfg.get('network', 'wifi_country', fallback='FR')
    _set_wifi_country(wifi_country, platinfo)

    # Hostname
    hostname = cfg.get('system', 'hostname', fallback='')
    if hostname:
        _set_hostname(hostname)

    # Timezone
    tz = cfg.get('system', 'timezone', fallback='')
    if tz:
        utils.run(f'timedatectl set-timezone "{tz}"', check=False)
        ui.success(f"Timezone: {tz}")

    mark_bootstrapped()
    ui.success("Bootstrap complete")


# ── Individual bootstrap steps ──────────────────────────────────────


def _update_system():
    ui.info("Updating system packages...")
    # Dedicated ro-rootfs players never want background apt: on dormant
    # images unattended-upgrades wakes with the full backlog and holds
    # the dpkg lock for ages (biennale mini-07, 2026-07-22). All
    # platforms, not just x86.
    utils.run('systemctl stop unattended-upgrades', check=False)
    for svc in ('unattended-upgrades.service', 'apt-daily.timer',
                'apt-daily-upgrade.timer'):
        utils.run(f'systemctl disable --now {svc}', check=False)
    utils.run('apt update')
    utils.run('DEBIAN_FRONTEND=noninteractive apt upgrade -y', check=False)


def _configure_locale():
    ui.info("Configuring locale...")
    utils.run('sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen', check=False)
    utils.run('locale-gen', check=False)
    utils.run('update-locale LANG=en_US.UTF-8', check=False)
    ui.success("Locale configured (en_US.UTF-8)")


def _configure_ssh():
    ui.info("Configuring SSH...")
    sshd_conf = '/etc/ssh/sshd_config'
    if os.path.isfile(sshd_conf):
        with open(sshd_conf) as f:
            content = f.read()

        content = re.sub(r'#?PermitRootLogin\s+.*', 'PermitRootLogin yes', content)
        content = re.sub(r'#?PasswordAuthentication\s+.*', 'PasswordAuthentication yes', content)
        content = content.replace('UsePAM yes', 'UsePAM no')

        if 'IPQoS' not in content:
            content += '\nIPQoS cs0 cs0\n'

        # Disable locale forwarding to prevent client/server locale mismatch
        content = re.sub(r'^\s*AcceptEnv\s+LANG.*$', '# AcceptEnv LANG LC_*',
                         content, flags=re.MULTILINE)

        with open(sshd_conf, 'w') as f:
            f.write(content)

    # Remove cloud-init ssh override
    cloud_ssh = '/etc/ssh/sshd_config.d/50-cloud-init.conf'
    if os.path.isfile(cloud_ssh):
        os.remove(cloud_ssh)

    # Generate root SSH key if missing
    if not os.path.isfile('/root/.ssh/id_rsa'):
        os.makedirs('/root/.ssh', mode=0o700, exist_ok=True)
        utils.run('ssh-keygen -q -N "" -f /root/.ssh/id_rsa', check=False)

    utils.run('systemctl restart sshd || systemctl restart ssh', check=False)
    ui.success("SSH configured")


def _set_password(cfg):
    password = cfg.get('system', 'password', fallback='rootpi')
    subprocess.run(['chpasswd'], input=f'root:{password}\n', text=True, check=False)
    ui.success("Root password set")


def _install_base_packages():
    ui.info("Installing base packages...")
    utils.apt_install(
        'git', 'wget', 'curl', 'tmux', 'htop', 'lsof', 'nano',
        'imagemagick', 'build-essential', 'lm-sensors'
    )
    ui.success("Base packages installed")


def _install_python():
    ui.info("Installing Python3...")
    utils.apt_install('python3', 'python3-pip', 'python3-setuptools')
    ui.success("Python3 installed")


def _install_nodejs():
    ui.info("Installing Node.js...")
    utils.apt_install('nodejs', 'npm')
    utils.run('npm i -g n', check=False)
    # nodejs.org stopped shipping armv7l/armv6l binaries after the 18.x
    # line: `n lts` (>=20) finds nothing there and the distro node stays
    # (Buster: node 10 — too old for webconf). Pin 18 on 32-bit ARM;
    # everything else gets the real LTS.
    if platform_mod.machine() in ('armv7l', 'armv6l'):
        utils.run('n 18', check=False)
    else:
        utils.run('n lts', check=False)
    # Ensure new node is found
    os.environ['PATH'] = '/usr/local/bin:' + os.environ.get('PATH', '')
    utils.run('npm install -g npm pm2 nodemon', check=False)
    ui.success("Node.js installed")


def _install_uv():
    ui.info("Installing uv (Python package manager)...")
    utils.run('curl -LsSf https://astral.sh/uv/install.sh | sh', check=False)
    # The installer drops uv in /root/.local/bin — invisible to systemd
    # units (HPlayer2's launcher does `command -v uv` under the default
    # service PATH and never starts without this link).
    for tool in ('uv', 'uvx'):
        src = os.path.expanduser(f'~/.local/bin/{tool}')
        if os.path.isfile(src):
            utils.run(f'ln -sf "{src}" /usr/local/bin/{tool}', check=False)
    ui.success("uv installed (linked into /usr/local/bin)")


def _install_mosquitto():
    ui.info("Installing Mosquitto...")
    utils.apt_install('mosquitto')
    utils.disable_service('mosquitto')
    ui.success("Mosquitto installed (disabled by default)")


def _install_avahi():
    ui.info("Installing Avahi/mDNS...")
    utils.apt_install('avahi-daemon', 'avahi-utils', 'libnss-mdns')
    avahi_conf = '/etc/avahi/avahi-daemon.conf'
    if os.path.isfile(avahi_conf):
        with open(avahi_conf) as f:
            content = f.read()
        content = content.replace('use-ipv6=yes', 'use-ipv6=no')
        with open(avahi_conf, 'w') as f:
            f.write(content)
    utils.enable_service('avahi-daemon')
    utils.run('systemctl start avahi-daemon', check=False)
    ui.success("Avahi installed")


def _install_haveged():
    ui.info("Installing haveged...")
    utils.apt_install('haveged')
    utils.enable_service('haveged')
    utils.run('systemctl start haveged', check=False)
    ui.success("Haveged installed")


def _setup_network_manager(platinfo):
    ui.info("Setting up NetworkManager + dnsmasq...")
    utils.apt_install('network-manager', 'dnsmasq')

    # Disable competing network managers. dhcpcd is the Raspbian
    # Buster/Bullseye default and fights NetworkManager for the
    # interfaces (and rewrites resolv.conf) if left enabled.
    for svc in ['systemd-networkd.socket', 'systemd-resolved', 'systemd-networkd',
                'dhcpcd', 'dhcpcd5']:
        utils.run(f'systemctl stop {svc}', check=False)
        utils.disable_service(svc)

    # DNS
    resolv = '/etc/resolv.conf'
    if os.path.islink(resolv):
        os.remove(resolv)
    with open(resolv, 'w') as f:
        f.write("nameserver 1.1.1.1\nnameserver 1.0.0.1\n")

    # NetworkManager config
    nm_conf = '/etc/NetworkManager/NetworkManager.conf'
    os.makedirs(os.path.dirname(nm_conf), exist_ok=True)
    with open(nm_conf, 'w') as f:
        f.write("[main]\n"
                "plugins=keyfile\n"
                "dns=none\n\n"
                "[connection]\n"
                "wifi.powersave = 2\n\n"
                "[keyfile]\n"
                "unmanaged-devices=interface-name:p2p-dev-*\n")

    os.makedirs('/etc/dnsmasq.d', exist_ok=True)
    utils.enable_service('dnsmasq')

    # x86: Netplan → NetworkManager
    if platinfo['is_x86']:
        netplan_dir = '/etc/netplan'
        if os.path.isdir(netplan_dir):
            for fn in os.listdir(netplan_dir):
                if fn.endswith('.yaml'):
                    os.remove(os.path.join(netplan_dir, fn))
            with open(os.path.join(netplan_dir, '01-netcfg.yaml'), 'w') as f:
                f.write("network:\n  version: 2\n  renderer: NetworkManager\n")
            os.chmod(os.path.join(netplan_dir, '01-netcfg.yaml'), 0o600)
            utils.run('netplan generate', check=False)
            utils.run('netplan apply', check=False)

    utils.enable_service('NetworkManager.service')
    utils.run('systemctl restart NetworkManager.service', check=False)
    utils.disable_service('NetworkManager-wait-online.service')
    ui.success("NetworkManager configured")


def _disable_ipv6(platinfo):
    ui.info("Disabling IPv6...")
    ifaces = ['all', 'lo', 'eth0', 'wlan0', 'wlan1', 'wint']
    if platinfo['is_x86']:
        ifaces.extend(['enp1s0', 'enp2s0', 'eth1'])

    lines = ['# Disable IPv6']
    for iface in ifaces:
        lines.append(f'net.ipv6.conf.{iface}.disable_ipv6=1')

    with open('/etc/sysctl.d/40-ipv6.conf', 'w') as f:
        f.write('\n'.join(lines) + '\n')
    ui.success("IPv6 disabled")


def _quiet_boot(platinfo):
    ui.info("Configuring quiet boot...")
    utils.disable_service('getty@tty1')

    if platinfo['is_pi']:
        cmdline_path = os.path.join(platinfo['boot_dir'], 'cmdline.txt')
        if os.path.isfile(cmdline_path):
            with open(cmdline_path) as f:
                cmdline = f.read().strip()

            # Add quiet options
            for opt in ['logo.nologo', 'consoleblank=0', 'quiet', 'loglevel=3',
                        'vt.global_cursor_default=0', 'net.ifnames=0']:
                if opt not in cmdline:
                    cmdline += f' {opt}'

            # Redirect console away from tty1
            cmdline = cmdline.replace('console=tty1', 'console=tty3')

            with open(cmdline_path, 'w') as f:
                f.write(cmdline + '\n')

    elif platinfo['is_x86']:
        grub_default = '/etc/default/grub'
        if os.path.isfile(grub_default):
            with open(grub_default) as f:
                content = f.read()
            content = re.sub(
                r'GRUB_CMDLINE_LINUX=""',
                'GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"',
                content
            )
            with open(grub_default, 'w') as f:
                f.write(content)
            utils.run('update-grub', check=False)

    # Cursor fix
    bashrc = '/root/.bashrc'
    if os.path.isfile(bashrc):
        with open(bashrc) as f:
            content = f.read()
        if 'setterm -cursor on' not in content:
            with open(bashrc, 'a') as f:
                f.write('\nsetterm -cursor on\n')
    ui.success("Quiet boot configured")


def _install_ohmybash():
    ui.info("Installing oh-my-bash...")
    bashrc = '/root/.bashrc'
    if os.path.isfile(bashrc):
        with open(bashrc) as f:
            content = f.read()
        additions = []
        for line in ['DISABLE_UPDATE_PROMPT=true', 'DISABLE_AUTO_UPDATE=true']:
            if line not in content:
                additions.append(line)
        if additions:
            with open(bashrc, 'a') as f:
                f.write('\n' + '\n'.join(additions) + '\n')

    utils.run(
        'RUNZSH=no bash -c "$(wget -q https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh -O -)" --unattended',
        check=False
    )
    ui.success("oh-my-bash installed")


# ── Platform-specific bootstrap ─────────────────────────────────────


def _bootstrap_pi(platinfo, cfg):
    """Raspberry Pi specific bootstrap."""
    ui.info("Applying Raspberry Pi settings...")

    # i2c module
    modules_dir = '/etc/modules-load.d'
    os.makedirs(modules_dir, exist_ok=True)
    modules_file = os.path.join(modules_dir, 'raspberrypi.conf')
    existing = ''
    if os.path.isfile(modules_file):
        with open(modules_file) as f:
            existing = f.read()
    if 'i2c-dev' not in existing:
        with open(modules_file, 'a') as f:
            f.write('i2c-dev\n')

    # Pi-specific packages (ignore failures — some may not exist on all versions)
    utils.apt_install('python3-rpi.gpio')

    # config.txt
    resolution = cfg.get('display', 'resolution', fallback='1920x1080@30')
    config_txt = os.path.join(platinfo['boot_dir'], 'config.txt')
    if os.path.isfile(config_txt):
        import shutil
        bak = config_txt + '.origin'
        if not os.path.isfile(bak):
            shutil.copy2(config_txt, bak)

        with open(config_txt, 'w') as f:
            f.write(f"""#
# Pi-tools config.txt
#

# Hardware overlays
dtparam=audio=on
dtparam=i2c_arm=on

# Global settings
arm_64bit=1
arm_boost=1
force_turbo=1
camera_auto_detect=1
display_auto_detect=1
auto_initramfs=1

# Fast boot
boot_delay=0
disable_splash=1

# GPU — DRM VC4 V3D driver
dtoverlay=vc4-kms-v3d
max_framebuffers=2
disable_fw_kms_setup=1
disable_overscan=1

# Resolution
video=HDMI-A-1:{resolution.replace('@', 'M@')}

[pi3]
gpu_mem=200

[pi4]
gpu_mem=400

[pi5]
gpu_mem=512
""")

    # Touch fix (iiyama)
    cmdline_path = os.path.join(platinfo['boot_dir'], 'cmdline.txt')
    if os.path.isfile(cmdline_path):
        with open(cmdline_path) as f:
            cmdline = f.read().strip()
        if 'usbhid.mousepoll=0' not in cmdline:
            cmdline += ' usbhid.mousepoll=0'
            with open(cmdline_path, 'w') as f:
                f.write(cmdline + '\n')

    # Internal WiFi rename to wint
    udev_rule = '/etc/udev/rules.d/72-static-name.rules'
    if not os.path.isfile(udev_rule):
        with open(udev_rule, 'w') as f:
            f.write('ACTION=="add", SUBSYSTEM=="net", DRIVERS=="brcmfmac", NAME="wint"\n')
        utils.run('udevadm control --reload', check=False)

    # Version marker
    version_file = os.path.join(platinfo['boot_dir'], 'VERSION')
    with open(version_file, 'w') as f:
        f.write("Pi-tools -- bootstrapped via setup.sh\n")

    ui.success("Raspberry Pi configured")


def _bootstrap_x86(platinfo):
    """x86 specific bootstrap."""
    ui.info("Applying x86 settings...")

    # Disable unnecessary services (unattended-upgrades handled in
    # _update_system for all platforms)
    for svc in ['iscsid.socket', 'iscsid.service', 'open-iscsi.service',
                'systemd-networkd-wait-online.service']:
        utils.run(f'systemctl disable --now {svc}', check=False)

    # Internal WiFi rename to wint
    udev_rule = '/etc/udev/rules.d/72-static-name.rules'
    if not os.path.isfile(udev_rule):
        with open(udev_rule, 'w') as f:
            f.write('ACTION=="add", SUBSYSTEM=="net", DRIVERS=="iwlwifi", NAME="wint"\n')
        utils.run('udevadm control --reload', check=False)

    ui.success("x86 configured")


def _set_wifi_country(country, platinfo):
    """Set WiFi regulatory country."""
    utils.run(f'iw reg set {country}', check=False)
    if platinfo['is_pi']:
        utils.run(f'raspi-config nonint do_wifi_country {country}', check=False)
    ui.success(f"WiFi country: {country}")


def _set_hostname(hostname):
    """Set system hostname."""
    with open('/etc/hostname', 'w') as f:
        f.write(hostname + '\n')

    # Ensure hostname resolves in /etc/hosts
    hosts_file = '/etc/hosts'
    if os.path.isfile(hosts_file):
        with open(hosts_file) as f:
            content = f.read()
        # Update or add 127.0.1.1 entry
        entry = f'127.0.1.1\t{hostname}'
        if re.search(r'^127\.0\.1\.1\s', content, re.MULTILINE):
            content = re.sub(r'^127\.0\.1\.1\s.*$', entry, content, flags=re.MULTILINE)
        else:
            content = content.rstrip('\n') + f'\n{entry}\n'
        with open(hosts_file, 'w') as f:
            f.write(content)

    utils.run(f'hostnamectl set-hostname "{hostname}"', check=False)
    ui.success(f"Hostname: {hostname}")
