// Slices a 20 mm cube in headless Chromium and checks the G-code for the U1.
// Usage: npm run build && npm test   (writes test/out/cube.gcode)

import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.resolve(here, '../dist');

const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };

// stands in for the app's WKURLSchemeHandler: serves dist/ at the root
function serve() {
    const server = http.createServer(async (req, res) => {
        let file = path.join(dist, decodeURIComponent(new URL(req.url, 'http://x').pathname));
        if (file.endsWith('/')) file = path.join(file, 'index.html');
        try {
            const body = await fs.readFile(file);
            res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
            res.end(body);
        } catch {
            res.writeHead(404).end();
        }
    });
    return new Promise(resolve => server.listen(0, () => resolve(server)));
}

function boxSTL(x, y = x, z = x) {
    const v = [[0,0,0],[x,0,0],[x,y,0],[0,y,0],[0,0,z],[x,0,z],[x,y,z],[0,y,z]];
    const faces = [[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],[1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7]];
    const buf = Buffer.alloc(84 + faces.length * 50);
    buf.writeUInt32LE(faces.length, 80);
    faces.forEach((f, i) => {
        const o = 84 + i * 50 + 12;
        f.forEach((vi, j) => v[vi].forEach((c, k) => buf.writeFloatLE(c, o + j * 12 + k * 4)));
    });
    return buf.toString('base64');
}

function check(name, ok) {
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`);
    if (!ok) process.exitCode = 1;
}

const server = await serve();
const browser = await chromium.launch();
try {
    const page = await browser.newPage();
    page.on('console', msg => { if (msg.type() === 'error') console.log('[page]', msg.text()); });
    page.on('pageerror', err => console.log('[page error]', err.message));
    await page.goto(`http://localhost:${server.address().port}/`);
    await page.waitForFunction(() => self.snarwal, null, { timeout: 30000 });

    const started = Date.now();
    const result = await page.evaluate(stl => self.snarwal.slice({ stl }), boxSTL(20));
    console.log(`sliced in ${Date.now() - started} ms:`, { layers: result.layers, printTimeS: result.printTimeS, filamentMM: result.filamentMM });

    await fs.mkdir(path.join(here, 'out'), { recursive: true });
    await fs.writeFile(path.join(here, 'out/cube.gcode'), result.gcode);

    const g = result.gcode;
    const moves = [...g.matchAll(/^G1 X([\d.]+) Y([\d.]+).* E[\d.]+/gm)].map(m => [Number(m[1]), Number(m[2])]);
    const xs = moves.map(m => m[0]), ys = moves.map(m => m[1]);
    check('starts the U1 print sequence', g.includes('PRINT_START') && g.includes('BED_MESH_CALIBRATE'));
    check('ends with PRINT_END', g.includes('PRINT_END'));
    check('no unresolved template variables', !/\{[a-z_]+[^}]*\}/.test(g));
    check('100 layers for 20 mm at 0.2 mm', result.layers === 100);
    check('extrusion moves present', moves.length > 1000);
    check('cube lies near bed centre (125..145 mm)', Math.min(...xs) > 120 && Math.max(...xs) < 150 && Math.min(...ys) > 120 && Math.max(...ys) < 150);
    check('no tool change for a single-tool print', !g.includes('Change Tool'));

    // a thin 300 mm bar slices quickly but cannot fit the 270 mm bed
    const tooBig = await page.evaluate(stl => self.snarwal.slice({ stl }).then(() => 'sliced', e => e.message), boxSTL(300, 10, 0.4));
    check('refuses a model larger than the bed', tooBig.startsWith('G-code leaves the bed'));
} finally {
    await browser.close();
    server.close();
}
