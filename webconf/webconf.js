const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const fs = require('fs');
const path = require('path');
const os = require('os');
const bonjour = require('bonjour')();
const { exec } = require('./utils');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

const port = 4038;

// Load settings files
const settingsPath = path.join(__dirname, 'settings');
const settingsFiles = fs.readdirSync(settingsPath);


class Server {
    constructor(port) {
        this.port = port;
        this.settings = {};
        this.refresh();

        app.use(express.static(path.join(__dirname, 'www')));

        io.on('connection', (socket) => {
            console.log('Client connected');
            socket.emit('name', os.hostname());
            socket.emit('settings', this.getSettings());

            socket.on('disconnect', () => {
                console.log('Client disconnected');
            });

            socket.on('update', (values) => {
                exec('rw');
                for (const [key, value] of Object.entries(values)) {
                    let [section, element] = key.split('.');
                    section = parseInt(section);
                    console.log('section:', section, 'element:', element, 'value:', value);
                    if (section in this.settings && element in this.settings[section].elements)
                        if (typeof this.settings[section].elements[element].apply === 'function') {
                            this.settings[section].elements[element].apply(value);
                            exec('sync');
                        }
                }
                exec('setnet');
                exec('ro');
                exec('nmcli c d eth0');
                this.refresh();
                socket.emit('settings', this.getSettings());
                console.log('updated: ', values);
                if (values.reboot) {
                    exec('reboot');
                }
            });
        });

        this.serverThread = null;
    }

    refresh() {
        this.settings = []

        for (const file of settingsFiles) {
            const settings = require(path.join(settingsPath, file));
            // check if settings.elements is not empty
            if (Object.keys(settings.elements).length) {
                this.settings.push(settings);
            }
        }
    }

    getSettings() {
        const sets = JSON.parse(JSON.stringify(this.settings));
        
        for (const i in sets) {
            for (const key in sets[i].elements) {
                if (typeof this.settings[i].elements[key].value === 'function') {
                    sets[i].elements[key].value = this.settings[i].elements[key].value();
                }
                if (typeof sets[i].elements[key].apply === 'function') {
                    delete sets[i].elements[key].apply;
                }
            }
        }
        return sets;
    }


    start() {
        server.listen(this.port, () => {
            console.log(`Web server started on port ${this.port}`);
        });

        this.bonjourService = bonjour.publish({
            name: `webconf._${os.hostname()}._http._tcp.local.`,
            type: 'http',
            port: this.port,
            txt: {},
            host: `${os.hostname()}.local.`
        });
    }

    stop() {
        this.bonjourService.stop();
        server.close(() => {
            console.log('Web server stopped');
        });
    }
}

const serverInstance = new Server(port);
serverInstance.start();

process.on('SIGINT', () => {
    serverInstance.stop();
    process.exit();
});

// setInterval(() => {
//     const memoryUsage = process.memoryUsage();
//     console.log(`Memory Usage: 
//     RSS: ${(memoryUsage.rss / 1024 / 1024).toFixed(2)} MB, 
//     Heap Total: ${(memoryUsage.heapTotal / 1024 / 1024).toFixed(2)} MB, 
//     Heap Used: ${(memoryUsage.heapUsed / 1024 / 1024).toFixed(2)} MB`);
// }, 5000); // Logs every 5 seconds