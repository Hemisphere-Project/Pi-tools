const { getLine, replaceLine } = require('../utils');

const settings = {
    'title': 'NAME',
    'elements': {}
};

if (getLine('hostrename@', '/boot/starter.txt')[0] !== '#') {
    settings.elements['hostname'] = {
        label: 'Name',
        field: 'text|15',
        legend: '<br /><br />',
        value: () => { return getLine('hostrename@', '/boot/starter.txt').split('@')[1].split('#')[0].trim() },
        apply: (value) => replaceLine('hostrename@', 'hostrename@' + value.trim(), '/boot/starter.txt')
    };
}

module.exports = settings;