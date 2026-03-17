/**
 * ZeroConf / Bonjour service discovery module for webconf.
 * Merged from the standalone 3615-disco service.
 */

const { Bonjour } = require('bonjour-service');
const os = require('os');

const bonjour = new Bonjour();

function getAllIP() {
    return Object.values(os.networkInterfaces())
        .flat()
        .filter(iface => iface.family === 'IPv4' && !iface.internal)
        .map(iface => iface.address)
        .filter(ip => ip !== '127.0.0.1');
}

class ZeroDevice {
    constructor(host) {
        this.host = host;
        this.ip = [];
        this.services = {};
    }

    add(service) {
        if (service.addresses) {
            for (const address of service.addresses) {
                if (address.includes(':')) continue;
                if (this.ip.includes(address)) continue;
                this.ip.push(address);
            }
        }
        if (service.fqdn in this.services) return false;
        this.services[service.fqdn] = service;
        return true;
    }

    remove(service) {
        if (service.fqdn in this.services) {
            delete this.services[service.fqdn];
            return true;
        }
        return false;
    }

    export() {
        return JSON.stringify(this);
    }
}

class ZeroDisco {
    constructor(io) {
        this.io = io;
        this.browsers = {};
        this.devices = {};
    }

    stop() {
        bonjour.destroy();
    }

    find(type, protocol = 'tcp') {
        const typePath = `_${type}._${protocol}`;
        this.browsers[typePath] = true;
    }

    start() {
        this.finder = bonjour.find({});
        this.finder.on('up', (service) => {
            delete service.rawTxt;
            delete service.txt;
            if (!(service.host in this.devices))
                this.devices[service.host] = new ZeroDevice(service.host);
            if (this.devices[service.host].add(service))
                this.io.emit('device-update', this.devices[service.host].export());
        });
        this.finder.on('down', (service) => {
            if (!(service.host in this.devices)) return;
            if (this.devices[service.host].remove(service))
                this.io.emit('device-update', this.devices[service.host].export());
        });
    }

    sendAll(socket) {
        for (const host in this.devices)
            socket.emit('device-update', this.devices[host].export());
    }

    export() {
        return JSON.stringify(this.devices);
    }
}

function startDisco(io, bonjourPort) {
    const zero = new ZeroDisco(io);

    const services = ['dummy', 'http', 'http-api', 'mqtt', 'mqttc', 'apple-midi', 'osc', 'smb'];
    services.forEach(service =>
        zero.find(service, service === 'apple-midi' || service === 'osc' ? 'udp' : 'tcp'));

    zero.start();

    // Advertise self
    bonjour.publish({
        name: '3615',
        type: 'http',
        protocol: 'tcp',
        port: bonjourPort,
        txt: {},
        host: `${os.hostname()}.local`,
        addresses: getAllIP()
    });

    return zero;
}

module.exports = { startDisco };
