const { getLine, replaceLine, bootPath } = require('../utils');

const settings = {
    'title': 'DISPLAY',
    'elements': {}
};

const configTxt = bootPath('config.txt');

if (getLine('hdmi_mode=', configTxt)) {
    settings.elements['hdmi'] = {
        label: 'HDMI resolution',
        field: 'select|1080p[82],720p[85],1600x1200[51],1366x768[81],1024x768[16],800x600[9]',
        legend: '<br /><br />',
        value: () => { const l = getLine('hdmi_mode=', configTxt); return l ? l.split('=')[1].split('#')[0].trim() : ''; },
        apply: (value) => replaceLine('hdmi_mode=', 'hdmi_mode=' + parseInt(value), configTxt)
    };
}

module.exports = settings;
