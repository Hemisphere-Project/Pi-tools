const { getLine, replaceLine, bootPath } = require('../utils');
const fs = require('fs');

const settings = {
    'title': 'WIFI',
    'elements': {}
};

const hotspotFile = bootPath('wifi', 'wint-hotspot.nmconnection');
const starterTxt = bootPath('starter.txt');

if (fs.existsSync(hotspotFile)) {
    settings.elements['wifipass'] = {
        label: 'Admin-wifi password',
        field: 'text|15',
        legend: '8 char. minimum',
        value: () => { const l = getLine('psk=', hotspotFile); return l ? l.split('=')[1].split('#')[0].trim() : ''; },
        apply: (value) => replaceLine('psk=', 'psk=' + value.trim(), hotspotFile)
    };
}

const woffLine = getLine('wint-off@', starterTxt);
if (fs.existsSync(hotspotFile) || (woffLine && woffLine[0] !== '#')) {
    settings.elements['wlan-off'] = {
        label: 'Admin-wifi OFF',
        field: 'text|15',
        legend: 'seconds (0 to disable WIFI-OFF)<br /><br />',
        value: () => { const l = getLine('wint-off@', starterTxt); return l ? l.split('@')[1].split('#')[0].trim() : ''; },
        apply: (value) => replaceLine('wint-off@', 'wint-off@' + parseInt(value), starterTxt)
    };
}

module.exports = settings;
