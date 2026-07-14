const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const bonjour = require('bonjour')();
const os = require('os');
const ifaces = os.networkInterfaces();

class EventEmitter {
    constructor(log = false) {
        this._eventHandlers = {};
        this._doLog = log;
    }

    trigger(eventName, args = null) {
        if (this._doLog) {
            console.log("event:", eventName, "/ args:", args);
        }

        if ('*' in this._eventHandlers) {
            for (const clbk of this._eventHandlers['*']) {
                clbk(eventName, args);
            }
        }

        if (eventName in this._eventHandlers) {
            for (const clbk of this._eventHandlers[eventName]) {
                clbk(args);
            }
        }
    }

    on(eventName, handler = null) {
        if (!Array.isArray(eventName)) {
            eventName = [eventName];
        }

        const registerHandler = (handler) => {
            for (const e of eventName) {
                if (e in this._eventHandlers) {
                    this._eventHandlers[e].push(handler);
                } else {
                    this._eventHandlers[e] = [handler];
                }
            }
            return handler;
        };

        if (handler) {
            registerHandler(handler);
        } else {
            return registerHandler;
        }
    }
}

function getAllIP() {
    const ip = [];
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

class FlaskServer extends EventEmitter {
    constructor(port) {
        super();
        this.port = port;

        const app = express();
        const server = http.createServer(app);
        const io = socketIo(server);

        this.io = io;

        app.use(express.static('www'));

        app.get('/', (req, res) => {
            this.trigger('index');
            res.sendFile(__dirname + '/www/index.html');
        });

        io.on('connection', (socket) => {
            console.log('connect');
            this.trigger('connect');
            socket.emit('name', os.hostname());
            console.log('name', os.hostname());

            socket.on('disconnect', () => {
                this.trigger('disconnect');
                console.log("Client disconnected");
            });
        });

        this.server = server;
    }

    start() {
        this.server.listen(this.port, () => {
            console.log(`Web server started on port ${this.port}`);
        });

        const hostname = os.hostname();
        const addresses = getAllIP();

        this.service = bonjour.publish({
            name: `3615._${hostname}._http._tcp.local.`,
            type: 'http',
            port: this.port,
            txt: {},
            host: `${hostname}.local`,
            addresses: addresses
        });
    }

    stop() {
        this.service.stop();
        console.log("Web server stopped");
    }
}

class ZeroService {
    constructor(fullname, type) {
        this.fullname = fullname;
        this.serviceName = fullname.replace(type, '').split('.')[0];
        this.serviceHost = fullname.replace(type, '').split('.')[1].substring(1);
        this.type = type;

        const service = bonjour.findOne({ type: type, name: fullname });
        if (service) {
            this.addresses = service.addresses.map(addr => `${addr}:${service.port}`);
            this.host = service.host.split('.')[0];
            this.ip = service.addresses;
            this.port = service.port;
            this.validDevice = true;
            this.validConfig = true;
        } else {
            this.validDevice = false;
            this.validConfig = false;
        }
    }
}

class ZeroDevice {
    constructor(ip, host) {
        this.ip = [ip];
        this.host = host;
        this.services = {};
    }

    add(service) {
        service.validDevice = (service.ip.includes(this.ip)) && (this.host === service.host);
        this.services[service.fullname] = service;
        return service;
    }

    export() {
        return JSON.stringify(this);
    }
}

class ZeroDisco extends EventEmitter {
    constructor() {
        super();
        this.browsers = {};
        this.devices = {};
    }

    stop() {
        bonjour.destroy();
    }

    add(type, protocol = 'tcp') {
        const typePath = `_${type}._${protocol}.local.`;
        if (!(typePath in this.browsers)) {
            this.browsers[typePath] = bonjour.find({ type: typePath }, this.onServiceStateChange.bind(this));
        }
    }

    export() {
        return JSON.stringify(this.devices);
    }

    onServiceStateChange(service) {
        if (service.fqdn.endsWith('.local.')) {
            this.serviceAdd(service.name, service.type);
        } else {
            this.serviceRemove(service.name, service.type);
        }
    }

    serviceAdd(name, serviceType) {
        console.log(`ADD ${name} of type ${serviceType}`);
        const service = new ZeroService(name, serviceType);

        if (service.validConfig) {
            if (!(service.host in this.devices)) {
                this.devices[service.host] = new ZeroDevice(service.ip, service.host);
                this.trigger('device-new', this.devices[service.host].export());
            }

            if (!this.devices[service.host].ip.includes(service.ip)) {
                this.devices[service.host].ip.push(service.ip);
            }

            if (service.fullname in this.devices[service.host].services) {
                delete this.devices[service.host].services[service.fullname];
                this.trigger('service-remove', JSON.stringify({ host: service.host, service: service.fullname }));
            }

            const newService = this.devices[service.host].add(service);
            this.trigger('service-add', JSON.stringify({ host: service.host, service: newService }));
        }
    }

    serviceRemove(name, serviceType) {
        console.log(`REMOVE ${name} of type ${serviceType}`);
        for (const host in this.devices) {
            if (name in this.devices[host].services) {
                delete this.devices[host].services[name];
                this.trigger('service-remove', JSON.stringify({ host: host, service: name }));
            }
        }
    }
}

const config = { port: 80 };

const flask = new FlaskServer(config.port);
flask.start();

const zero = new ZeroDisco();

zero.on('*', (event, data) => {
    flask.io.emit(event, data);
});

flask.on('connect', () => {
    flask.io.emit('init', zero.export());
});

zero.add('dummy');
zero.add('http');
zero.add('http-api');
zero.add('mqtt');
zero.add('mqttc');
zero.add('apple-midi', 'udp');
zero.add('osc', 'udp');

process.on('SIGINT', () => {
    zero.stop();
    flask.stop();
    console.log("Goodbye!");
    process.exit();
});