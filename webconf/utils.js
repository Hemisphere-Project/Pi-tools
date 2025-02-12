const fs = require('fs');
const { networkInterfaces } = require('os');
const { execSync } = require('child_process');

function exec(command) {
    try {
        execSync(command);
    }
    catch (err) {
        // console.error(err);
    }
}

function getAllIp() {
    const nets = networkInterfaces();
    const results = [];

    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                results.push(net.address);
            }
        }
    }
    return results;
}

function getLine(string, file) {
    try {
        const data = fs.readFileSync(file, 'utf8');
        const lines = data.split('\n');
        for (const line of lines) {
            if (line.includes(string)) {
                return line;
            }
        }
    } catch (err) {
        console.error(err);
    }
    return null;
}

function replaceLine(find, replace, file) {
    try {
        const data = fs.readFileSync(file, 'utf8');
        const lines = data.split('\n');
        const newLines = lines.map(line => {
            if (line.includes(find)) {
                const comment = line.split('#').slice(1).join('#').trim();
                line = replace;
                if (comment) {
                    line += ' # ' + comment;
                }
            }
            return line;
        });
        fs.writeFileSync(file, newLines.join('\n'), 'utf8');
    } catch (err) {
        console.error(err);
    }
}

function commentLine(find, file) {
    try {
        const data = fs.readFileSync(file, 'utf8');
        const lines = data.split('\n');
        const newLines = lines.map(line => {
            if (line.includes(find) && !line.trim().startsWith('#')) {
                line = '# ' + line.trim();
            }
            return line;
        });
        fs.writeFileSync(file, newLines.join('\n'), 'utf8');
    } catch (err) {
        console.error(err);
    }
}

function uncommentLine(find, file) {
    try {
        const data = fs.readFileSync(file, 'utf8');
        const lines = data.split('\n');
        const newLines = lines.map(line => {
            if (line.includes(find) && line.trim().startsWith('#')) {
                line = line.slice(1).trim();
            }
            return line;
        });
        fs.writeFileSync(file, newLines.join('\n'), 'utf8');
    } catch (err) {
        console.error(err);
    }
}

module.exports = {
    exec,
    getAllIp,
    getLine,
    replaceLine,
    commentLine,
    uncommentLine
};