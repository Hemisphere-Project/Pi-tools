const { getLine, replaceLine } = require('../utils');

const settings = {
    'title': 'DISPLAY',
    'elements': {}
};

if (getLine('hdmi_mode=', '/boot/firmware/config.txt')) {
    settings.elements['hdmi'] = {
        label: 'HDMI resolution',
        field: 'select|1080p[82],720p[85],1600x1200[51],1366x768[81],1024x768[16],800x600[9]',
        legend: '<br /><br />',
        value: () => {return getLine('hdmi_mode=', '/boot/firmware/config.txt').split('=')[1].split('#')[0].trim()},
        apply: (value) => replaceLine('hdmi_mode=', 'hdmi_mode=' + parseInt(value), '/boot/firmware/config.txt')
    };
}

module.exports = settings;