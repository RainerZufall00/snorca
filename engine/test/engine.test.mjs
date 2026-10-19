// End-to-end tests for the engine bundle in headless Chromium.
// Usage: npm run build && npm test   (G-code lands in test/out/)

import { chromium } from 'playwright';
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.resolve(here, '../dist');
const require = createRequire(import.meta.url);
const JSZip = require('../../vendor/grid-apps/node_modules/jszip');

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

const faces = [[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],[1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7]];
const corners = (x, y, z, ox = 0, oy = 0) =>
    [[0,0,0],[x,0,0],[x,y,0],[0,y,0],[0,0,z],[x,0,z],[x,y,z],[0,y,z]].map(([a, b, c]) => [a + ox, b + oy, c]);

// triangle soup (9 floats per triangle) for a box with its min corner at (ox, oy, 0)
function boxFloats(x, y, z, ox = 0, oy = 0) {
    const v = corners(x, y, z, ox, oy);
    return Buffer.from(new Float32Array(faces.flatMap(f => f.flatMap(i => v[i]))).buffer).toString('base64');
}

function boxSTL(x, y = x, z = x) {
    const v = corners(x, y, z);
    const buf = Buffer.alloc(84 + faces.length * 50);
    buf.writeUInt32LE(faces.length, 80);
    faces.forEach((f, i) => {
        const o = 84 + i * 50 + 12;
        f.forEach((vi, j) => v[vi].forEach((c, k) => buf.writeFloatLE(c, o + j * 12 + k * 4)));
    });
    return buf.toString('base64');
}

// minimal Orca-style 3MF: two boxes placed by build transforms, extruders in model_settings.config
async function orca3MF() {
    const mesh = (x, y, z) => {
        const v = corners(x, y, z);
        return `<mesh><vertices>${v.map(([a, b, c]) => `<vertex x="${a}" y="${b}" z="${c}"/>`).join('')}</vertices>` +
            `<triangles>${faces.map(([a, b, c]) => `<triangle v1="${a}" v2="${b}" v3="${c}"/>`).join('')}</triangles></mesh>`;
    };
    const model = `<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
<resources>
<object id="1" type="model" name="Sockel">${mesh(30, 30, 6)}</object>
<object id="2" type="model" name="Turm">${mesh(10, 10, 20)}</object>
</resources>
<build>
<item objectid="1" transform="1 0 0 0 1 0 0 0 1 40 40 0"/>
<item objectid="2" transform="1 0 0 0 1 0 0 0 1 200 190 0"/>
</build>
</model>`;
    const settings = `<?xml version="1.0" encoding="UTF-8"?>
<config>
<object id="1"><metadata key="name" value="Sockel"/><metadata key="extruder" value="1"/></object>
<object id="2"><metadata key="name" value="Turm"/><metadata key="extruder" value="3"/></object>
</config>`;
    const zip = new JSZip();
    zip.file('3D/3dmodel.model', model);
    zip.file('Metadata/model_settings.config', settings);
    return (await zip.generateAsync({ type: 'nodebuffer' })).toString('base64');
}

function extrusionBox(gcode) {
    const moves = [...gcode.matchAll(/^G1 X([\d.]+) Y([\d.]+).* E[\d.]+/gm)].map(m => [Number(m[1]), Number(m[2])]);
    const xs = moves.map(m => m[0]), ys = moves.map(m => m[1]);
    return { count: moves.length, minX: Math.min(...xs), maxX: Math.max(...xs), minY: Math.min(...ys), maxY: Math.max(...ys) };
}

let failures = 0;
function check(name, ok, detail = '') {
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok || !detail ? '' : `  (${detail})`}`);
    if (!ok) failures++;
}

const server = await serve();
const browser = await chromium.launch();
const out = path.join(here, 'out');
await fs.mkdir(out, { recursive: true });
try {
    const page = await browser.newPage();
    page.on('pageerror', err => console.log('[page error]', err.message));
    await page.goto(`http://localhost:${server.address().port}/`);
    await page.waitForFunction(() => self.snarwal, null, { timeout: 30000 });

    // 1. STL import + single-tool slice, model centred on the bed
    const loaded = await page.evaluate(data => self.snarwal.loadModel({ name: 'Wuerfel.stl', data }), boxSTL(20));
    check('STL loads as one object', loaded.objects.length === 1 && loaded.objects[0].name === 'Wuerfel');
    const cube = boxFloats(20, 20, 20, 125, 125);
    let started = Date.now();
    const single = await page.evaluate(v => self.snarwal.slice({ objects: [{ vertices: v, tool: 0 }] }), cube);
    console.log(`     cube sliced in ${Date.now() - started} ms`, { layers: single.layers, printTimeS: single.printTimeS, filamentMM: single.filamentMM });
    await fs.writeFile(path.join(out, 'cube.gcode'), single.gcode);
    const g = single.gcode, b = extrusionBox(g);
    check('starts the U1 print sequence', g.includes('PRINT_START') && g.includes('BED_MESH_CALIBRATE'));
    check('ends with PRINT_END', g.includes('PRINT_END'));
    check('no unresolved template variables', !/\{[a-z_]+[^}]*\}/.test(g));
    check('100 layers for 20 mm at 0.2 mm', single.layers === 100, single.layers);
    check('cube printed at 125..145 mm', b.minX > 123 && b.maxX < 147 && b.minY > 123 && b.maxY < 147, JSON.stringify(b));
    check('no tool change for a single-tool print', !g.includes('Change Tool'));

    // 2. two objects on two tools keep their bed positions
    started = Date.now();
    const multi = await page.evaluate(([a, c]) => self.snarwal.slice({ objects: [{ vertices: a, tool: 0 }, { vertices: c, tool: 1 }] }),
        [boxFloats(20, 20, 10, 30, 30), boxFloats(20, 20, 10, 210, 200)]);
    console.log(`     two tools sliced in ${Date.now() - started} ms`);
    await fs.writeFile(path.join(out, 'two-tools.gcode'), multi.gcode);
    const changes = (multi.gcode.match(/^T\d/gm) ?? []);
    check('tool changes between T0 and T1', multi.gcode.includes('Change Tool0 -> Tool1') && multi.gcode.includes('Change Tool1 -> Tool0'));
    check('second head is primed after a change', multi.gcode.includes('SM_PRINT_PREEXTRUDE_FILAMENT INDEX=1'));
    const mb = extrusionBox(multi.gcode);
    check('objects stay at their X/Y positions', mb.minX > 28 && mb.minX < 33 && mb.maxX > 228 && mb.maxX < 232 && mb.minY > 28 && mb.maxY > 218 && mb.maxY < 222, JSON.stringify(mb));
    check('T commands only select real heads', changes.every(t => /^T[0-3]$/.test(t)), changes.join(','));
    check('filament is counted per head', multi.toolsMM[0] > 100 && multi.toolsMM[1] > 100 && multi.toolsMM[2] === 0, JSON.stringify(multi.toolsMM));

    // 2a. thumbnails land after the header block in Prusa format
    const png = Buffer.from('89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000D4944415478DA63F8FFFF3F0005FE02FEA7D7A3C20000000049454E44AE426082', 'hex').toString('base64');
    const withThumb = await page.evaluate(([v, png]) => self.snarwal.slice({ objects: [{ vertices: v, tool: 0 }], thumbnails: [{ width: 1, height: 1, png }] }),
        [boxFloats(10, 10, 2, 100, 100), png]);
    const head = withThumb.gcode.slice(0, 2000);
    await fs.writeFile(path.join(out, 'thumb.gcode'), withThumb.gcode);
    check('thumbnail block follows the header', /; HEADER_BLOCK_END\n; THUMBNAIL_BLOCK_START\n; thumbnail begin 1x1 \d+\n(; [A-Za-z0-9+/=]+\n)+; thumbnail end/.test(head));

    // 2b. Moonraker (Snapmaker fork) only parses Prusa/Orca-style metadata
    const mg = multi.gcode;
    check('header identifies an Orca-format file', /OrcaSlicer\s(.*)\son/.test(mg.slice(0, 4096)));
    check('footer has print time for Moonraker', /; estimated printing time \(normal mode\) = (\d+h )?\d+m \d+s/.test(mg.slice(-4096)));
    check('footer has per-head filament', /; filament used \[g\] = [\d.]+,[\d.]+,0\.00,0\.00/.test(mg));
    check('layer heights are tagged like Orca', /;BEFORE_LAYER_CHANGE\n;0\.2/.test(mg));

    // 3. Orca 3MF keeps names, positions and extruder assignment
    const three = await page.evaluate(async data => {
        const { objects } = await self.snarwal.loadModel({ name: 'Set.3mf', data });
        const box = o => {
            const bin = atob(o.vertices), f = new Float32Array(Uint8Array.from(bin, c => c.charCodeAt(0)).buffer);
            let minX = Infinity, minY = Infinity;
            for (let i = 0; i < f.length; i += 3) { minX = Math.min(minX, f[i]); minY = Math.min(minY, f[i + 1]); }
            return { minX, minY };
        };
        return objects.map(o => ({ name: o.name, tool: o.tool, painted: o.painted, ...box(o) }));
    }, await orca3MF());
    check('3MF yields both objects', three.length === 2, JSON.stringify(three));
    check('3MF names come from Orca metadata', three.map(o => o.name).join() === 'Sockel,Turm');
    check('3MF extruders map to tools 0 and 2', three.map(o => o.tool).join() === '0,2');
    check('3MF build transforms are applied', three[1].minX === 200 && three[1].minY === 190, JSON.stringify(three[1]));
    check('unpainted 3MF is not flagged', three.every(o => !o.painted));

    // 3b. automatic supports under an overhang (T shape: pillar + wide top)
    const tee = (() => {
        const decode = b => {
            const buf = Buffer.from(b, 'base64'); // pooled: respect byteOffset
            return Array.from(new Float32Array(buf.buffer, buf.byteOffset, buf.length / 4));
        };
        const pillar = decode(boxFloats(10, 10, 20, 130, 130));
        const top = decode(boxFloats(40, 40, 4, 115, 115)).map((v, i) => i % 3 === 2 ? v + 20 : v);
        return Buffer.from(new Float32Array([...pillar, ...top]).buffer).toString('base64');
    })();
    const supported = await page.evaluate(v => self.snarwal.slice({ objects: [{ vertices: v, tool: 0 }],
        process: { sliceSupportType: 'automatic' } }), tee);
    const unsupported = await page.evaluate(v => self.snarwal.slice({ objects: [{ vertices: v, tool: 0 }],
        process: { sliceSupportType: 'disabled' } }), tee);
    check('automatic supports add support paths', /; feature support/.test(supported.gcode) && !/; feature support/.test(unsupported.gcode));
    check('supports cost extra filament', supported.filamentMM > unsupported.filamentMM, `${supported.filamentMM} vs ${unsupported.filamentMM}`);

    // 4. safety: nothing may leave the bed
    const tooBig = await page.evaluate(v => self.snarwal.slice({ objects: [{ vertices: v, tool: 0 }] }).then(() => 'sliced', e => e.message),
        boxFloats(300, 10, 0.4, -15, 100));
    check('refuses a model larger than the bed', tooBig.startsWith('G-code leaves the bed'), tooBig);
} finally {
    await browser.close();
    server.close();
}
if (failures) {
    console.log(`${failures} check(s) failed`);
    process.exitCode = 1;
}
