const { getLine, replaceLine, exec } = require('../utils');
const fs = require('fs');

var syncIface;

const wlan0Files = [
    '/boot/wifi/wlan0-sync-AP.nmconnection',
    '/boot/wifi/wlan0-sync-STA.nmconnection',
    '/boot/wifi/_disabled/wlan0-sync-AP.nmconnection',
    '/boot/wifi/_disabled/wlan0-sync-STA.nmconnection'
];

const settings = {
    'title': 'SYNC',
    'elements': {}
};

settings.elements['synciface'] = {
    label: 'SYNC interface',
    field: 'select|eth0[0],wlan0[1]',
    legend: 'eth0: wired / wlan0: wifi usb dongle',
    value: () => { return fs.existsSync('/boot/wifi/eth0-sync-STA.nmconnection') || fs.existsSync('/boot/wifi/eth0-sync-AP.nmconnection') ? 0 : 1; },
    apply: (value) => syncIface = parseInt(value)
};

settings.elements['syncmode'] = {
    label: 'SYNC mode',
    field: 'select|disable[0],slave[1],master[2]',
    legend: '',
    value: () => {
        if (fs.existsSync('/boot/wifi/wlan0-sync-AP.nmconnection') || fs.existsSync('/boot/wifi/eth0-sync-AP.nmconnection')) {
            return 2;
        } else if (fs.existsSync('/boot/wifi/wlan0-sync-STA.nmconnection') || fs.existsSync('/boot/wifi/eth0-sync-STA.nmconnection')) {
            return 1;
        } else {
            return 0;
        }
    },
    apply: (mode) => {
        mode = parseInt(mode);
        exec('rm /boot/wifi/wlan0-*');
        exec('rm /boot/wifi/eth0-*');
        if (syncIface === 0) {
            if (mode === 1) exec('cp /boot/wifi/_disabled/eth0-sync-STA.nmconnection /boot/wifi/eth0-sync-STA.nmconnection');
            else if (mode === 2) exec('cp /boot/wifi/_disabled/eth0-sync-AP.nmconnection /boot/wifi/eth0-sync-AP.nmconnection');
            else exec('cp /boot/wifi/_disabled/eth0-dhcp.nmconnection /boot/wifi/eth0-dhcp.nmconnection');
        } else if (syncIface === 1) {
            if (mode === 1) exec('cp /boot/wifi/_disabled/wlan0-sync-STA.nmconnection /boot/wifi/wlan0-sync-STA.nmconnection');
            else if (mode === 2) exec('cp /boot/wifi/_disabled/wlan0-sync-AP.nmconnection /boot/wifi/wlan0-sync-AP.nmconnection');
            exec('cp /boot/wifi/_disabled/eth0-dhcp.nmconnection /boot/wifi/eth0-dhcp.nmconnection');
        }
    }
};

settings.elements['syncchannel'] = {
    label: 'SYNC channel',
    field: 'text|3',
    legend: 'channel alias for Wifi Sync (allows distinct sync network, wifi only)<br /><br />',
    value: () =>{
        let ssid = '';
        for (const file of wlan0Files) {
            if (fs.existsSync(file)) {
                ssid = getLine('ssid=', file).split('=')[1].split('#')[0].trim();
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