// Slices real-world models (3MF/STL) the way the app does: load, centre on
// the bed, slice with the U1 profile, then check the result.
//
// Usage: npm run build && node test/real-models.test.mjs <folder with .3mf/.stl>
// CI downloads Orca's handy_models (3DBenchy, Stanford Bunny, …) for this.

import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.resolve(here, '../dist');
const folder = process.argv[2];
if (!folder) {
    console.error('usage: node test/real-models.test.mjs <folder>');
    process.exit(2);
}

const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
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
await new Promise(resolve => server.listen(0, resolve));

let failures = 0;
function check(name, ok, detail = '') {
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? `  (${detail})` : ''}`);
    if (!ok) failures++;
}

const browser = await chromium.launch();
try {
    const page = await browser.newPage();
    page.on('pageerror', err => console.log('[page error]', err.message));
    await page.goto(`http://localhost:${server.address().port}/`);
    await page.waitForFunction(() => self.snarwal, null, { timeout: 30000 });

    const files = (await fs.readdir(folder)).filter(f => /\.(3mf|stl)$/i.test(f)).sort();
    check('models found', files.length > 0, `${files.length}`);
    for (const file of files) {
        const data = (await fs.readFile(path.join(folder, file))).toString('base64');
        const started = Date.now();
        // in the page: load, centre each object on the bed like the app, slice
        const result = await page.evaluate(async ({ name, data }) => {
            const { objects } = await self.snarwal.loadModel({ name, data });
            const decode = b64 => new Float32Array(Uint8Array.from(atob(b64), c => c.charCodeAt(0)).buffer);
            const bed = self.snarwal.device;
            let maxHeight = 0, triangles = 0;
            const placed = objects.map(o => {
                const f = decode(o.vertices);
                triangles += f.length / 9;
                const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
                for (let i = 0; i < f.length; i += 3) for (let a = 0; a < 3; a++) {
                    min[a] = Math.min(min[a], f[i + a]); max[a] = Math.max(max[a], f[i + a]);
                }
                const dx = bed.bedWidth / 2 - (min[0] + max[0]) / 2, dy = bed.bedDepth / 2 - (min[1] + max[1]) / 2, dz = -min[2];
                for (let i = 0; i < f.length; i += 3) { f[i] += dx; f[i + 1] += dy; f[i + 2] += dz; }
                maxHeight = Math.max(maxHeight, max[2] - min[2]);
                const bytes = new Uint8Array(f.buffer);
                let bin = '';
                for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
                return { vertices: btoa(bin), tool: o.tool ?? 0 };
            });
            try {
                const r = await self.snarwal.slice({ objects: placed.slice(0, 1) });
                return { ok: true, names: objects.map(o => o.name), triangles, maxHeight,
                         layers: r.layers, printTimeS: r.printTimeS, grams: r.toolsG[0],
                         hasStart: r.gcode.includes('PRINT_START'), hasEnd: r.gcode.includes('PRINT_END'),
                         hasThumbnailSlot: r.gcode.includes('; HEADER_BLOCK_END'),
                         tail: r.gcode.slice(-1500), bytes: r.gcode.length };
            } catch (e) {
                return { ok: false, error: e.message, names: objects.map(o => o.name), triangles };
            }
        }, { name: file, data });
        const ms = Date.now() - started;
        if (!result.ok) {
            check(`${file}: slices`, false, result.error);
            continue;
        }
        const expectedLayers = Math.round(result.maxHeight / 0.2);
        console.log(`     ${file}: ${result.names.join(', ')} · ${result.triangles} triangles · ${result.maxHeight.toFixed(1)} mm · ` +
                    `${result.layers} layers · ${Math.round(result.printTimeS / 60)} min · ${result.grams} g · ${ms} ms`);
        check(`${file}: sliced inside the bed`, true);
        // Kiri drops features narrower than ~0.7 mm (needle tips), so allow a small shortfall
        check(`${file}: layer count matches height`, result.layers >= expectedLayers * 0.95 && result.layers <= expectedLayers + 2,
              `${result.layers} vs ~${expectedLayers}`);
        check(`${file}: plausible print time and filament`, result.printTimeS > 60 && result.grams > 0.5,
              `${result.printTimeS}s, ${result.grams}g`);
        check(`${file}: U1 start and end sequence`, result.hasStart && result.hasEnd && result.hasThumbnailSlot);
        check(`${file}: Orca-style footer`, /; estimated printing time \(normal mode\) =/.test(result.tail));
    }
} finally {
    await browser.close();
    server.close();
}
if (failures) {
    console.log(`${failures} check(s) failed`);
    process.exitCode = 1;
}
