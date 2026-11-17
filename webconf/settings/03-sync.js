const { getLine, replaceLine, exec, bootPath } = require('../utils');
const fs = require('fs');
const path = require('path');

var syncIface;

const wifiDir = bootPath('wifi');

// Profile templates for a role switch: the card's own wifi/_disabled/ copy
// first, else this checkout's network-tools/profiles (_disabled/ holds the sync
// roles, the top level eth0-dhcp). An installer-made card has no _disabled/ on
// its boot partition (network-tools/README.md), and since RastaOS-7.5 setnet
// makes the NM store exactly /boot/wifi: a copy that silently failed after the
// rm below used to leave no eth0 profile at all, and the card lost its way in
// at the next boot.
const repoProfiles = path.join(__dirname, '..', '..', 'network-tools', 'profiles');
function template(role) {
    const name = role + '.nmconnection';
    for (const p of [path.join(wifiDir, '_disabled', name),
                     path.join(repoProfiles, '_disabled', name),
                     path.join(repoProfiles, name)]) {
        if (fs.existsSync(p)) return p;
    }
    return null;
}

// The /boot/wifi profiles a (sync interface, sync mode) pair needs; null when
// the interface is unknown (the panel sent no SYNC interface).
function rolesFor(iface, mode) {
    if (iface === 0) return [mode === 1 ? 'eth0-sync-STA' : mode === 2 ? 'eth0-sync-AP' : 'eth0-dhcp'];
    if (iface === 1) {
        const roles = mode === 1 ? ['wlan0-sync-STA'] : mode === 2 ? ['wlan0-sync-AP'] : [];
        return roles.concat(['eth0-dhcp']);
    }
    return null;
}
const wlan0Files = [
    path.join(wifiDir, 'wlan0-sync-AP.nmconnection'),
    path.join(wifiDir, 'wlan0-sync-STA.nmconnection'),
    path.join(wifiDir, '_disabled', 'wlan0-sync-AP.nmconnection'),
    path.join(wifiDir, '_disabled', 'wlan0-sync-STA.nmconnection')
];

const settings = {
    'title': 'SYNC',
    'elements': {}
};

settings.elements['synciface'] = {
    label: 'SYNC interface',
    field: 'select|eth0[0],wlan0[1]',
    legend: 'eth0: wired / wlan0: wifi usb dongle',
    value: () => { return fs.existsSync(path.join(wifiDir, 'eth0-sync-STA.nmconnection')) || fs.existsSync(path.join(wifiDir, 'eth0-sync-AP.nmconnection')) ? 0 : 1; },
    apply: (value) => syncIface = parseInt(value)
};

settings.elements['syncmode'] = {
    label: 'SYNC mode',
    field: 'select|disable[0],slave[1],master[2]',
    legend: '',
    value: () => {
        if (fs.existsSync(path.join(wifiDir, 'wlan0-sync-AP.nmconnection')) || fs.existsSync(path.join(wifiDir, 'eth0-sync-AP.nmconnection'))) {
            return 2;
        } else if (fs.existsSync(path.join(wifiDir, 'wlan0-sync-STA.nmconnection')) || fs.existsSync(path.join(wifiDir, 'eth0-sync-STA.nmconnection'))) {
            return 1;
        } else {
            return 0;
        }
    },
    apply: (mode) => {
        mode = parseInt(mode);
        const roles = rolesFor(syncIface, mode);
        if (!roles) {
            console.error('[sync] no SYNC interface given — /boot/wifi left as it is');
            return;
        }
        // Resolve every template BEFORE removing anything: a missing one leaves
        // the card's profiles untouched instead of leaving it with none.
        const sources = roles.map(template);
        const missing = roles.filter((r, i) => !sources[i]);
        if (missing.length) {
            console.error(`[sync] no template for ${missing.join(', ')} — /boot/wifi left as it is`);
            return;
        }
        exec(`rm -f ${wifiDir}/wlan0-* ${wifiDir}/eth0-*`);
        roles.forEach((r, i) => exec(`cp "${sources[i]}" "${path.join(wifiDir, r + '.nmconnection')}"`));
    }
};

settings.elements['syncchannel'] = {
    label: 'SYNC channel',
    field: 'text|3',
    legend: 'channel alias for Wifi Sync (allows distinct sync network, wifi only)<br /><br />',
    value: () => {
        let ssid = '';
        for (const file of wlan0Files) {
            if (fs.existsSync(file)) {
                const l = getLine('ssid=', file);
                ssid = l ? l.split('=')[1].split('#')[0].trim() : '';
                break;
            }
        }
        return ssid.split('-').pop();
    },
    apply: (channel) => {
        for (const file of wlan0Files) {
            if (fs.existsSync(file)) {
                replaceLine('ssid=', 'ssid=synclink-' + channel, file);
            }
        }
    }
};

module.exports = settings;
