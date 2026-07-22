#!/usr/bin/env python3
"""Pi-tools installer — main orchestrator.

Usage:
    sudo ./setup.sh          # Normal interactive install
    sudo ./setup.sh --yes    # Accept all defaults (non-interactive)
"""

import os
import sys
import shutil
import platform as platform_mod
import configparser

# Ensure imports work when run as: python3 setup/installer.py
SETUP_DIR = os.path.dirname(os.path.abspath(__file__))
PITOOLS_DIR = os.path.dirname(SETUP_DIR)
sys.path.insert(0, PITOOLS_DIR)

from setup import ui, detect, config, utils, bootstrap


# ── Module group definitions ────────────────────────────────────────
# (group_key, description, [module_dirs], default_setting)

MODULE_GROUPS = [
    ('system',      'System (read-only root + USB automount)',
     ['rorw', 'usbautomount'], 'yes'),
    ('network',     'Network (WiFi profiles + hostname)',
     ['network-tools', 'hostrename'], 'yes'),
    ('web',         'Web UIs (config + file manager + discovery)',
     ['webconf', 'filebrother'], 'ask'),
    ('audiohub',    'Audio hub: always-on multi-output (jack/HDMI/USB)',
     ['audiohub'], 'ask'),
    ('xrun',        'X11/Openbox display server',
     ['xrun'], 'no'),
    ('synczinc',    'Syncthing synchronization',
     ['synczinc'], 'no'),
    ('bluetooth',   'Bluetooth controller',
     ['bluetooth-pi'], 'no'),
    ('rtpmidi',     'RTP MIDI (CoreMIDI)',
     ['rtpmidi'], 'no'),
    ('tailscale',   'Tailscale VPN',
     ['tailscale'], 'ask'),
]

CORE_MODULES = ['starter', 'extendfs', 'splash']


# ── Module installation ─────────────────────────────────────────────


def discover_module(name):
    """Find module directory and parse its module.ini."""
    module_dir = os.path.join(PITOOLS_DIR, name)
    ini_path = os.path.join(module_dir, 'module.ini')
    if not os.path.isfile(ini_path):
        return None, None
    ini = configparser.ConfigParser()
    ini.read(ini_path)
    return module_dir, ini


def check_platform(ini, platinfo):
    """Check if module supports current platform."""
    platforms = ini.get('module', 'platforms', fallback='pi,x86')
    platforms = [p.strip() for p in platforms.split(',')]
    if platinfo['is_pi'] and 'pi' not in platforms:
        return False
    if platinfo['is_x86'] and 'x86' not in platforms:
        return False
    return True


def install_module(name, platinfo, cfg):
    """Install a single module based on its module.ini."""
    module_dir, ini = discover_module(name)
    if not module_dir:
        ui.error(f"Module '{name}' has no module.ini")
        return False

    if not check_platform(ini, platinfo):
        ui.skip(f"{name}: not supported on this platform")
        return True

    desc = ini.get('module', 'description', fallback=name)
    ui.info(f"Installing {name} — {desc}")

    # If module has script=yes, use its install.sh for everything
    use_script = ini.getboolean('install', 'script', fallback=False)
    if use_script:
        script = os.path.join(module_dir, 'install.sh')
        if os.path.isfile(script):
            result = utils.run(f'bash "{script}"', cwd=module_dir, check=False)
            if result.returncode != 0:
                ui.error(f"{name}: install.sh failed (exit {result.returncode}) — not installed")
                return False
            ui.success(f"{name} installed (via install.sh)")
            return True

    # ── Standard module.ini-driven install ──

    # 1. Apt dependencies
    if ini.has_option('deps', 'apt'):
        pkgs = ini.get('deps', 'apt').strip()
        if pkgs:
            utils.apt_install(*pkgs.split())

    # 2. Create directories
    if ini.has_option('files', 'dirs'):
        for d in ini.get('files', 'dirs').split():
            os.makedirs(d, exist_ok=True)

    # 3. npm install
    if ini.getboolean('files', 'npm', fallback=False):
        utils.npm_install(module_dir)

    # 4. Link binaries
    if ini.has_option('files', 'bins'):
        for b in ini.get('files', 'bins').split():
            src = os.path.join(module_dir, b)
            if os.path.isfile(src):
                os.chmod(src, 0o755)
                utils.link_bin(src)

    # 5. Install services
    if ini.has_option('files', 'services'):
        for s in ini.get('files', 'services').split():
            src = os.path.join(module_dir, s)
            if os.path.isfile(src):
                utils.install_service(src)

    # 6. Install timers
    if ini.has_option('files', 'timers'):
        for t in ini.get('files', 'timers').split():
            src = os.path.join(module_dir, t)
            if os.path.isfile(src):
                utils.install_service(src)

    # 7. Udev rules
    if ini.has_option('files', 'udev_rules'):
        for r in ini.get('files', 'udev_rules').split():
            src = os.path.join(module_dir, r)
            if os.path.isfile(src):
                utils.install_udev_rule(src)
        utils.udev_reload()

    # 8. Enable services
    if ini.has_option('files', 'enable'):
        for s in ini.get('files', 'enable').split():
            utils.enable_service(s)

    # 9. Mask services
    if ini.has_option('files', 'mask'):
        for s in ini.get('files', 'mask').split():
            utils.mask_service(s)

    # 10. Post-install hook
    if name in POST_HOOKS:
        POST_HOOKS[name](module_dir, platinfo, cfg)

    # 11. Starter entry
    if ini.has_option('starter', 'comment') and ini.has_option('starter', 'service'):
        comment = ini.get('starter', 'comment')
        service = ini.get('starter', 'service')
        entry = f"## [{name}] {comment}\n# {service}\n"
        utils.append_starter(entry)

    utils.daemon_reload()
    ui.success(f"{name} installed")
    return True


# ── Post-install hooks ──────────────────────────────────────────────


def hook_starter(module_dir, platinfo, cfg):
    """Create initial starter.txt if missing, enable service."""
    path = utils.starter_txt_path()
    if not os.path.isfile(path):
        with open(path, 'w') as f:
            f.write("#\n"
                    "#  Pi-tools starter configuration\n"
                    "#  Services listed here are started at boot.\n"
                    "#  Uncomment a line to enable a service.\n"
                    "#\n\n")
    utils.enable_service('starter.service')


def hook_network_tools(module_dir, platinfo, cfg):
    """Configure dnsmasq and WiFi directory."""
    dnsmasq_conf = '/etc/dnsmasq.conf'
    with open(dnsmasq_conf, 'w') as f:
        f.write("listen-address=10.0.0.1\n"
                "dhcp-range=10.0.0.2,10.0.0.99,255.255.255.0,12h\n\n"
                "listen-address=10.1.0.1\n"
                "dhcp-range=10.1.0.2,10.1.0.99,255.255.255.0,12h\n\n"
                "dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases\n")

    boot_dir = utils.find_boot_dir()
    wifi_dir = os.path.join(boot_dir, 'wifi')
    os.makedirs(wifi_dir, exist_ok=True)

    # Honor hotspot=no: never seed an always-on AP profile. The shipped
    # *-hotspot.nmconnection has autoconnect=true, so copying it would bring up a
    # hotspot (with the default PSK) even when the operator disabled it.
    hotspot_enabled = cfg.get('network', 'hotspot', fallback='yes') == 'yes'

    # Copy default profiles
    profiles_dir = os.path.join(module_dir, 'profiles')
    if os.path.isdir(profiles_dir):
        for fn in os.listdir(profiles_dir):
            src = os.path.join(profiles_dir, fn)
            if not os.path.isfile(src):
                continue
            if 'hotspot' in fn and not hotspot_enabled:
                ui.skip(f"hotspot disabled — not seeding {fn}")
                continue
            dst = os.path.join(wifi_dir, fn)
            if not os.path.exists(dst):
                shutil.copy2(src, dst)

    # x86: the wint-hotspot template pins 5GHz (band=a/chan36 — tuned on the Pi's
    # Broadcom). Intel iwlwifi refuses AP on 5GHz until LAR regulatory settles and
    # NM then fails the whole hotspot (N100 pilot 2026-07-21); strip the pin so NM
    # falls back to 2.4GHz — the proven 2024 behaviour.
    if platinfo['is_x86']:
        hotspot_file = os.path.join(wifi_dir, 'wint-hotspot.nmconnection')
        if os.path.isfile(hotspot_file):
            with open(hotspot_file) as f:
                lines = f.readlines()
            kept = [l for l in lines if l.strip() not in ('band=a', 'channel=36')]
            if len(kept) != len(lines):
                with open(hotspot_file, 'w') as f:
                    f.writelines(kept)
                ui.info("x86: stripped 5GHz pin from wint-hotspot (2.4GHz fallback)")


def hook_bluetooth(module_dir, platinfo, cfg):
    """Enable Bluetooth auto-power-on."""
    bt_conf = '/etc/bluetooth/main.conf'
    if os.path.isfile(bt_conf):
        with open(bt_conf) as f:
            content = f.read()
        if 'AutoEnable=true' not in content:
            with open(bt_conf, 'a') as f:
                f.write('\nAutoEnable=true\n')


def hook_xrun(module_dir, platinfo, cfg):
    """Configure X11 environment."""
    # Create hmini user
    utils.run('id hmini &>/dev/null || useradd -m hmini', check=False)

    # Allow X from any user
    xwrapper = '/etc/X11/Xwrapper.config'
    if os.path.isfile(xwrapper):
        with open(xwrapper) as f:
            content = f.read()
        import re
        content = re.sub(r'^allowed_users=.*', 'allowed_users=anybody',
                         content, flags=re.MULTILINE)
        with open(xwrapper, 'w') as f:
            f.write(content)

    # Openbox autostart
    os.makedirs('/etc/xdg/openbox', exist_ok=True)
    dst = '/etc/xdg/openbox/autostart'
    src = os.path.join(module_dir, 'openbox-start')
    if os.path.lexists(dst):
        os.remove(dst)
    os.symlink(src, dst)
    os.chmod(src, 0o755)

    # xinitrc
    with open('/root/.xinitrc', 'w') as f:
        f.write('exec openbox-session\n')
    os.chmod('/root/.xinitrc', 0o755)

    # Remove picom autostart
    picom_desktop = '/etc/xdg/autostart/picom.desktop'
    if os.path.isfile(picom_desktop):
        os.remove(picom_desktop)


def hook_filebrother(module_dir, platinfo, cfg):
    """Download filebrowser binary."""
    if not os.path.isfile('/usr/local/bin/filebrowser'):
        utils.run('curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash',
                  check=False)
    os.makedirs('/data/var/filebrother', exist_ok=True)


def hook_synczinc(module_dir, platinfo, cfg):
    """Install syncthing from official repo."""
    list_file = '/etc/apt/sources.list.d/syncthing.list'
    if not os.path.isfile(list_file):
        utils.run(
            'curl -s https://syncthing.net/release-key.gpg | '
            'gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg',
            check=False)
        with open(list_file, 'w') as f:
            f.write('deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] '
                    'https://apt.syncthing.net/ syncthing stable\n')
        utils.run('apt update', check=False)
    utils.apt_install('syncthing')

    # Python 'syncthing' lib for master mode -> a uv venv on /data (RO-rootfs-safe;
    # system pip3 is refused under PEP-668). Best-effort: peer mode needs none of
    # this, and the wrapper falls back to peer if the venv is missing.
    if os.path.ismount('/data'):
        venv = '/data/var/synczinc/venv'
        os.makedirs('/data/var/synczinc', exist_ok=True)
        uv = shutil.which('uv') or '/root/.local/bin/uv'
        utils.run(f'{uv} venv "{venv}"', check=False)
        utils.run(f'{uv} pip install --python "{venv}/bin/python" syncthing', check=False)
    else:
        ui.warn("synczinc: /data not mounted — skipping master-mode venv (peer mode still works)")


POST_HOOKS = {
    'starter':       hook_starter,
    'network-tools': hook_network_tools,
    'bluetooth-pi':  hook_bluetooth,
    'xrun':          hook_xrun,
    'filebrother':   hook_filebrother,
    'synczinc':      hook_synczinc,
}


# ── WiFi setup from config ──────────────────────────────────────────


def _sanitize_filename(name):
    """Sanitize a string for use as a filename. Keeps alphanumeric, dash, underscore, space."""
    import re
    return re.sub(r'[^\w\s\-]', '_', name).strip()


def setup_wifi_from_config(cfg, platinfo):
    """Create WiFi .nmconnection profiles from pitools.txt config."""
    boot_dir = utils.find_boot_dir()
    wifi_dir = os.path.join(boot_dir, 'wifi')
    os.makedirs(wifi_dir, exist_ok=True)

    # Hotspot AP profile (SSID = hostname)
    if cfg.get('network', 'hotspot', fallback='yes') == 'yes':
        hostname = cfg.get('system', 'hostname', fallback='') or 'pitools'
        hotspot_pw = cfg.get('network', 'hotspot_password', fallback='raspberry')
        hotspot_file = os.path.join(wifi_dir, 'wint-hotspot.nmconnection')
        if not os.path.exists(hotspot_file):
            with open(hotspot_file, 'w') as f:
                f.write(f"[connection]\n"
                        f"id=hotspot-wint\n"
                        f"type=wifi\n"
                        f"autoconnect=true\n"
                        f"interface-name=wint\n\n"
                        f"[wifi]\n"
                        f"hidden=false\n"
                        f"mode=ap\n"
                        f"ssid={hostname}\n\n"
                        f"[wifi-security]\n"
                        f"key-mgmt=wpa-psk\n"
                        f"psk={hotspot_pw}\n\n"
                        f"[ipv4]\n"
                        f"address1=10.0.0.1/16,10.0.0.1\n"
                        f"method=manual\n\n"
                        f"[ipv6]\n"
                        f"method=disabled\n")
            os.chmod(hotspot_file, 0o600)
            ui.success(f"Hotspot profile created: {hostname} (wint)")

    # Client WiFi profiles
    networks = config.get_wifi_networks(cfg)
    if not networks:
        return

    for net in networks:
        ssid = net['ssid']
        password = net['password']
        safe_name = _sanitize_filename(ssid)
        if not safe_name:
            ui.warn(f"Skipping WiFi with empty/invalid SSID")
            continue
        filepath = os.path.join(wifi_dir, f"{safe_name}.nmconnection")

        if not os.path.exists(filepath):
            with open(filepath, 'w') as f:
                f.write(f"[connection]\n"
                        f"id={ssid}\n"
                        f"type=wifi\n"
                        f"autoconnect=true\n\n"
                        f"[wifi]\n"
                        f"ssid={ssid}\n"
                        f"mode=infrastructure\n\n"
                        f"[wifi-security]\n"
                        f"key-mgmt=wpa-psk\n"
                        f"psk={password}\n\n"
                        f"[ipv4]\n"
                        f"method=auto\n\n"
                        f"[ipv6]\n"
                        f"method=disabled\n")
            os.chmod(filepath, 0o600)
            ui.success(f"WiFi profile created: {ssid}")


# ── Main ─────────────────────────────────────────────────────────────


def main():
    # Unattended-first: a fresh install must run to completion without a prompt.
    # Force apt/dpkg non-interactive for every subprocess spawned from here.
    os.environ['DEBIAN_FRONTEND'] = 'noninteractive'

    ui.banner()

    auto_yes = '--yes' in sys.argv

    # Platform detection
    platinfo = detect.detect()
    if platinfo['is_pi']:
        pi_ver = platinfo['pi_model'] or '?'
        ui.info(f"Platform: Raspberry Pi {pi_ver}")
    elif platinfo['is_x86']:
        ui.info(f"Platform: x86_64")
    else:
        ui.warn(f"Platform: {platinfo['arch']} (best-effort)")

    ui.info(f"Boot partition: {platinfo['boot_dir']}")

    # Find config
    config_path = detect.find_config(platinfo)
    if config_path:
        ui.success(f"Config: {config_path}")
    else:
        ui.info("No pitools.txt found — using interactive mode")

    cfg = config.load(config_path)

    # Interactive prompts only on first run (no config file, not yet bootstrapped)
    # and only with a real terminal — under `curl | sudo bash` stdin is the pipe,
    # so input() would read from the script instead of the operator.
    if (not config_path and not auto_yes and not bootstrap.is_bootstrapped()
            and sys.stdin.isatty()):
        hostname = ui.ask_text("Hostname", default='')
        if hostname:
            cfg.set('system', 'hostname', hostname)

        tz = ui.ask_text("Timezone", default='Europe/Paris')
        if tz:
            cfg.set('system', 'timezone', tz)

        wifi_country = ui.ask_text("WiFi country code", default='FR')
        if wifi_country:
            cfg.set('network', 'wifi_country', wifi_country)

    # ── Bootstrap ──
    bootstrap.run_bootstrap(platinfo, cfg)

    # ── WiFi from config ──
    setup_wifi_from_config(cfg, platinfo)

    # ── Core modules (always installed) ──
    ui.header("Core Modules")
    for mod_name in CORE_MODULES:
        mod_dir = os.path.join(PITOOLS_DIR, mod_name)
        if utils.is_module_installed(mod_dir):
            ui.skip(f"{mod_name}: already installed")
        else:
            install_module(mod_name, platinfo, cfg)

    # Datesync (standalone HTTP time sync: script + timer, not a full module).
    # fake-clock (rorw) is the boot-time floor; the timer nudges the clock forward
    # from an HTTP Date header whenever a network is reachable (NTP-blocked LANs).
    datesync_src = os.path.join(PITOOLS_DIR, 'datesync')
    if os.path.isfile(datesync_src):
        os.chmod(datesync_src, 0o755)
        utils.link_bin(datesync_src)
        for unit in ('datesync.service', 'datesync.timer'):
            unit_src = os.path.join(PITOOLS_DIR, unit)
            if os.path.isfile(unit_src):
                utils.install_service(unit_src)
        utils.daemon_reload()
        utils.enable_service('datesync.timer')
        ui.success("datesync linked + timer enabled")

    # ── Optional module groups ──
    ui.header("Optional Modules")

    for group_key, group_desc, mod_names, default in MODULE_GROUPS:
        # Config setting
        setting = cfg.get('modules', group_key, fallback=default)

        # Check if already installed
        all_installed = all(
            utils.is_module_installed(os.path.join(PITOOLS_DIR, m))
            for m in mod_names
        )

        if all_installed:
            ui.skip(f"{group_desc}: already installed")
            continue

        # Decide
        if setting == 'no':
            ui.skip(f"{group_desc}: disabled")
            continue
        elif setting == 'ask':
            # 'ask' needs a human. With --yes, or with no TTY (piped
            # `curl | bash`), treat it as skip instead of silently accepting the
            # input() default — which would install without consent.
            if auto_yes or not sys.stdin.isatty():
                reason = '--yes mode' if auto_yes else 'non-interactive'
                ui.skip(f"{group_desc}: skipped ({reason})")
                continue
            if not ui.ask_yn(f"Install {group_desc}?"):
                ui.skip(f"{group_desc}: skipped")
                continue

        # Install each module in the group
        for mod_name in mod_names:
            if utils.is_module_installed(os.path.join(PITOOLS_DIR, mod_name)):
                ui.skip(f"  {mod_name}: already installed")
            else:
                install_module(mod_name, platinfo, cfg)

    # ── Done ──
    ui.header("Setup Complete")
    starter_path = utils.starter_txt_path()
    ui.success("Pi-tools installed!")
    ui.info(f"Edit {starter_path} to enable/disable services at boot")
    ui.info("Then reboot to apply.")
    print()


if __name__ == '__main__':
    main()
