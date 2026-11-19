// DY log collector v3 (dev machine): RAW TCP line listener -> appends ATV-pushed lines to a file.
// Run: node dy_collector.js
// ATV opens TCP to <dev-ip>:9988 and writes "<text>\n" per log line.
// History: v1 (PowerShell) serial accept loop -- one zombie connection starved ALL new
// connections forever (2026-11-20 zero-log night). v2 (PowerShell Task.Run) -- PS5.1
// scriptblocks on threadpool threads have no runspace, handlers silently failed, nothing
// was ever written. v3 = Node, per-socket handling is native and reliable.
const net = require('net');
const fs = require('fs');
const path = require('path');

const PORT = 9988;
const OUT = 'C:/Nbeetok/dy-tvos/output/atv_push.log';
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, '=== collector v3 started ' + new Date().toTimeString().slice(0, 8) + ' ===\n');
console.log('collector(TCP) v3 listening on :' + PORT + ' -> ' + OUT);

function stamp() { return new Date().toTimeString().slice(0, 8); }

const server = net.createServer((socket) => {
    const peer = socket.remoteAddress + ':' + socket.remotePort;
    console.log('[' + stamp() + '] client connected ' + peer);
    socket.setEncoding('utf8');
    let buf = '';
    socket.on('data', (chunk) => {
        buf += chunk;
        let idx;
        while ((idx = buf.indexOf('\n')) >= 0) {
            const line = buf.slice(0, idx).replace(/\r$/, '');
            buf = buf.slice(idx + 1);
            if (line.length > 0) {
                fs.appendFileSync(OUT, stamp() + '  ' + line + '\n');
            }
        }
    });
    socket.on('error', (e) => console.log('[' + stamp() + '] socket err ' + peer + ' ' + e.message));
    socket.on('close', () => console.log('[' + stamp() + '] client closed ' + peer));
});
server.listen(PORT, () => console.log('listening'));
server.on('error', (e) => { console.error('server err: ' + e.message); process.exit(1); });
