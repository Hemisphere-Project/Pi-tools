const { getLine, replaceLine, bootPath } = require('../utils');

const settings = {
    'title': 'NAME',
    'elements': {}
};

const starterTxt = bootPath('starter.txt');
const hostLine = getLine('hostrename@', starterTxt);

if (hostLine && hostLine[0] !== '#') {
    settings.elements['hostname'] = {
        label: 'Name',
        field: 'text|15',
        legend: '<br /><br />',
        value: () => { const l = getLine('hostrename@', starterTxt); return l ? l.split('@')[1].split('#')[0].trim() : ''; },
        apply: (value) => replaceLine('hostrename@', 'hostrename@' + value.trim(), starterTxt)
    };
}

module.exports = settings;
