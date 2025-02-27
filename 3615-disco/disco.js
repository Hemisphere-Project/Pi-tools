import express from 'express';
import http from 'http';
import { Server as SocketIoServer } from 'socket.io';
import { Bonjour } from 'bonjour-service';
import os from 'os';
import { execSync } from 'child_process';

import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const bonjour = new Bonjour();

const config = { port: 80 };

const app = express();
const server = http.createServer(app);
const io = new SocketIoServer(server);


function getAllIP() {
    const ip = [];
    const ifaces = os.networkInterfaces();
    for (const iface in ifaces) {
        if (iface.startsWith('e') || iface.startsWith('w')) {
            for (const alias of ifaces[iface]) {
                if (alias.family === 'IPv4' && !alias.internal) {
                    ip.push(alias.address);
                }
            }
        }
    }
    return ip;
}


class ZeroDevice {
    constructor(host) {
        this.host = host;
        this.ip = [];
        this.services = {};
    }

    add(service) {
        // add addresses to this.ip, keep only ipv4, avoid double
        if (service.addresses) {
            for (const address of service.addresses) {
                if (address.includes(':')) continue;
                if (this.ip.includes(address)) continue;
                this.ip.push(address);
            }
        }

        // add service to this.services if not already present (based on fqdn)
        if (service.fqdn in this.services) return false;
        this.services[service.fqdn] = service;
        return true;
    }

    remove(service) {
        // remove service from this.services
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
    constructor() {
        this.browsers = {};
        this.devices = {};
    }

    stop() {
        bonjour.destroy();
    }

    find(type, protocol = 'tcp') {
        const typePath = `_${type}._${protocol}`;
        console.log(`Watch for ${type} on ${protocol}`, typePath);
        this.browsers[typePath] = true;
    }

    filters(s) {
        return true;
        for (const type in this.browsers)
            if (s.fqdn.includes(type)) return true;
        return false;
    }

    start() {
        this.finder = bonjour.find({});
        this.finder.on('up', (service) => {
            if (!this.filters(service)) return;
            delete service.rawTxt;
            delete service.txt;
            console.log(`ADD ${service.name} to ${service.host}`);
            if (!(service.host in this.devices))
                this.devices[service.host] = new ZeroDevice(service.host);
            if (this.devices[service.host].add(service))
                io.emit('device-update', this.devices[service.host].export());
        });
        this.finder.on('down', (service) => {
            if (!this.filters(service)) return;
            if (!(service.host in this.devices)) return;
            console.log(`RM ${service.name} from ${service.host}`);
            if (this.devices[service.host].remove(service))
                io.emit('device-update', this.devices[service.host].export());
        });
    }

    export() {
        return JSON.stringify(this.devices);
    }
}

const zero = new ZeroDisco();

app.use(express.static(__dirname + '/www'));
app.get('/', (req, res) => {
    res.sendFile(__dirname + '/www/index.html');
});

// serve static files from /res

io.on('connection', (socket) => {
    socket.emit('name', os.hostname());

    for (const host in zero.devices) 
        socket.emit('device-update', zero.devices[host].export());

    socket.on('disconnect', () => {});
});

server.listen(config.port, () => {
    console.log(`Web server started on port ${config.port}`);
});

const services = ['dummy', 'http', 'http-api', 'mqtt', 'mqttc', 'apple-midi', 'osc', 'smb'];
services.forEach(service => zero.find(service, service === 'apple-midi' || service === 'osc' ? 'udp' : 'tcp'));

zero.start();

// advertise myself
var service = bonjour.publish({
    name: `3615`,
    type: 'http',
    protocol: 'tcp',
    port: config.port,
    txt: {},
    host: `${os.hostname()}.local`,
    addresses: getAllIP()
});

// restart avahi
execSync('sudo systemctl restart avahi-daemon');
console.log("Avahi restarted");

process.on('SIGINT', () => {
    zero.stop();
    service.stop();
    console.log("Goodbye!");
    process.exit();
});