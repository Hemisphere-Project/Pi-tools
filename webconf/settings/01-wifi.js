const { getLine, replaceLine } = require('../utils');
const fs = require('fs');

const settings = {
    'title': 'WIFI',
    'elements': {}
};

if (fs.existsSync('/boot/wifi/wint-hotspot.nmconnection')) {
    settings.elements['wifipass'] = {
        label: 'Admin-wifi password',
        field: 'text|15',
        legend: '8 char. minimum',
        value: () => {return getLine('psk=', '/boot/wifi/wint-hotspot.nmconnection').split('=')[1].split('#')[0].trim()},
        apply: (value) => replaceLine('psk=', 'psk=' + value.trim(), '/boot/wifi/wint-hotspot.nmconnection')
    };
}

if (fs.existsSync('/boot/wifi/wint-hotspot.nmconnection') || getLine('wint-off@', '/boot/starter.txt')[0] !== '#') {
    settings.elements['wlan-off'] = {
        label: 'Admin-wifi OFF',
        field: 'text|15',
        legend: 'seconds (0 to disable WIFI-OFF)<br /><br />',
        value: () => {return getLine('wint-off@', '/boot/starter.txt').split('@')[1].split('#')[0].trim()},
        apply: (value) => replaceLine('wint-off@', 'wint-off@' + parseInt(value), '/boot/starter.txt')
    };
}

module.exports = settings;