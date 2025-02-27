import os from 'os';
import fs from 'fs';
import path from 'path';
import { exec, execSync } from 'child_process';

// VAR path 
const DIR = '/data/var/filebrother/'
const PORT = 9000;
const ROOT = '/data';

const databasePath = path.join(DIR, 'database.db');
const configPath = path.join(DIR, 'config.json');

function getAllIP() {
    return Object.values(os.networkInterfaces())
        .flat()
        .filter(iface => iface.family === 'IPv4' && !iface.internal && (iface.address.startsWith('e') || iface.address.startsWith('w')))
        .map(iface => iface.address);
}

// add avahi service
execSync(`avahi-publish-service -s FileBrother _http._tcp ${PORT} &`, { stdio: 'inherit' });

console.log(`Starting FileBrother on port ${PORT}`);

// first confif if config.json does not exist
if (!fs.existsSync(configPath)) {
    // remove database if exists
    if (fs.existsSync(databasePath)) fs.unlinkSync(databasePath);
    execSync(`filebrowser -d ${databasePath} config init -p ${PORT} -r ${ROOT} -a '0.0.0.0' --auth.method=noauth`, { stdio: 'inherit' });
    execSync(`filebrowser -d ${databasePath} users add root rootpi`, { stdio: 'inherit' });
    execSync(`filebrowser -d ${databasePath} config export ${configPath}`, { stdio: 'inherit' });
}
let p = execSync(`filebrowser -c ${configPath} -d ${databasePath}`, { stdio: 'inherit' });
console.log(`FileBrother stopped`);

// ctrl-c
process.on('SIGINT', () => {
    console.log(`FileBrother stopped`);
    process.exit(0);
});