const fs = require('fs');
const path = require('path');
const { networkInterfaces } = require('os');
const { execSync } = require('child_process');

// Boot (FAT) partition: /boot/firmware on modern Pi OS (Bookworm), /boot on
// older images and x86. Resolve once so every panel reads the right files.
const BOOT_DIR = fs.existsSync('/boot/firmware') ? '/boot/firmware' : '/boot';
function bootPath(...parts) { return path.join(BOOT_DIR, ...parts); }

function exec(command) {
    try {
        execSync(command, { stdio: 'pipe' });
        return true;
    }
    catch (err) {
        console.error(`[exec] '${command}' failed:`, err.message);
        return false;
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
        // A missing boot file is a normal "not found -> null", not an error.
        if (err.code !== 'ENOENT') console.error(`[getLine] ${file}: ${err.message}`);
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
    uncommentLine,
    BOOT_DIR,
    bootPath
};