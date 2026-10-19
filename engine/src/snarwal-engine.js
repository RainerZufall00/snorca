// Bridge between the Snarwal app and the Kiri:Moto FDM engine.
//
// The app loads dist/index.html into a hidden WKWebView and calls:
//
//   await snarwal.loadModel({ name, data })
//     data: base64 (or ArrayBuffer) of an STL or 3MF file
//     → { objects: [{ name, tool, painted, vertices }] }
//       vertices: base64 Float32Array, 9 floats per triangle, millimetres.
//       For 3MF the build transforms are applied, so objects keep the
//       positions they had on the slicer plate. tool is 0-based or null.
//
//   await snarwal.slice({ objects, process })
//     objects: [{ vertices, tool }] with vertices in bed coordinates
//       (origin front-left, Z up), already rotated/scaled by the app
//     process: Kiri process overrides (temperatures, layer height, ...)
//     → { gcode, layers, printTimeS, filamentMM }
//
// Progress is posted to window.webkit.messageHandlers.snarwal when present.

import '../../vendor/grid-apps/src/add/array.js';
import '../../vendor/grid-apps/src/add/class.js';
import '../../vendor/grid-apps/src/add/three.js';
// api.js must load before workers.js (circular import), same order as Kiri's engine.js
import '../../vendor/grid-apps/src/kiri/app/api.js';
import { client } from '../../vendor/grid-apps/src/kiri/app/workers.js';
import { conf } from '../../vendor/grid-apps/src/kiri/app/conf/defaults.js';
import { newWidget } from '../../vendor/grid-apps/src/kiri/app/widget.js';
import { load } from '../../vendor/grid-apps/src/load/file.js';
import { parseAsync as parse3MF } from '../../vendor/grid-apps/src/load/3mf.js';
import { JSZip } from '../../vendor/grid-apps/src/ext/jszip-esm.js';
import { device, process as baseProcess } from '../profiles/snapmaker-u1.js';

export const version = '0.2.0';

client.setWorkPath(new URL('kiri/worker.js', location.href).href);
client.setPoolPath(new URL('kiri/pool.js', location.href).href);
client.restart();
client.pool.start();

function post(message) {
    try {
        self.webkit?.messageHandlers?.snarwal?.postMessage(message);
    } catch (e) {
        // not running inside the app
    }
}

function toArrayBuffer(data) {
    if (data instanceof ArrayBuffer) return data;
    if (ArrayBuffer.isView(data)) return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    if (typeof data === 'string') {
        const bin = atob(data);
        const out = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
        return out.buffer;
    }
    throw new Error('expected base64 string or ArrayBuffer');
}

function toBase64(floats) {
    const bytes = new Uint8Array(floats.buffer, floats.byteOffset, floats.byteLength);
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
        bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(bin);
}

function toFloats(vertices) {
    if (vertices instanceof Float32Array) return vertices;
    if (Array.isArray(vertices)) return new Float32Array(vertices);
    return new Float32Array(toArrayBuffer(vertices));
}

// ---- model loading -------------------------------------------------------

// Orca/Bambu keep per-object settings in Metadata/model_settings.config:
//   <object id="2"><metadata key="name" value="Clip"/><metadata key="extruder" value="3"/>
async function orcaObjectSettings(zip) {
    const file = zip.file('Metadata/model_settings.config');
    if (!file) return {};
    const doc = new DOMParser().parseFromString(await file.async('string'), 'text/xml');
    const settings = {};
    for (const object of doc.getElementsByTagName('object')) {
        const entry = {};
        for (const meta of object.children) {
            if (meta.tagName !== 'metadata') continue;
            const key = meta.getAttribute('key');
            if (key === 'name') entry.name = meta.getAttribute('value');
            if (key === 'extruder') entry.extruder = parseInt(meta.getAttribute('value'), 10);
        }
        settings[object.getAttribute('id')] = entry;
    }
    return settings;
}

// MMU painting is stored as paint_color (Orca/Bambu) or slic3rpe:mmu_segmentation (Prusa).
async function isPainted(zip) {
    for (const [name, file] of Object.entries(zip.files)) {
        if (!name.endsWith('.model')) continue;
        const xml = await file.async('string');
        if (xml.includes('paint_color=') || xml.includes('mmu_segmentation=')) return true;
    }
    return false;
}

async function load3MF(buffer, fallbackName) {
    const zip = await new JSZip().loadAsync(buffer);
    const [items, settings, painted] = await Promise.all([
        parse3MF(buffer), orcaObjectSettings(zip), isPainted(zip),
    ]);
    return items
        .filter(item => item.faces && item.faces.length >= 9)
        .map((item, i) => {
            const meta = settings[item.oid] ?? {};
            const extruder = meta.extruder;
            return {
                name: meta.name || item.name || `${fallbackName} ${i + 1}`,
                tool: Number.isInteger(extruder) && extruder >= 1 ? extruder - 1 : null,
                painted,
                vertices: toBase64(new Float32Array(item.faces)),
            };
        });
}

export async function loadModel({ name = 'Modell', data }) {
    const buffer = toArrayBuffer(data);
    const lower = name.toLowerCase();
    let objects;
    if (lower.endsWith('.3mf')) {
        objects = await load3MF(buffer, name.replace(/\.3mf$/i, ''));
    } else if (lower.endsWith('.stl')) {
        const vertices = new load.STL().parse(buffer);
        objects = [{ name: name.replace(/\.stl$/i, ''), tool: null, painted: false, vertices: toBase64(toFloats(vertices)) }];
    } else {
        throw new Error(`Unsupported file type: ${name}`);
    }
    if (!objects.length) throw new Error('The file contains no printable objects');
    return { objects };
}

// ---- slicing -------------------------------------------------------------

function bounds(floats) {
    const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < floats.length; i += 3) {
        for (let a = 0; a < 3; a++) {
            const v = floats[i + a];
            if (v < min[a]) min[a] = v;
            if (v > max[a]) max[a] = v;
        }
    }
    return { min, max };
}

function stats(gcode) {
    const filament = gcode.match(/; --- filament used: ([\d.]+) mm ---/);
    const time = gcode.match(/; --- print time: (\d+)s ---/);
    const layers = gcode.match(/; total layer number: (\d+)/);
    return {
        filamentMM: filament ? Number(filament[1]) : null,
        printTimeS: time ? Number(time[1]) : null,
        layers: layers ? Number(layers[1]) : null,
    };
}

function call(fn, ...args) {
    return new Promise((resolve, reject) => {
        fn(...args, reply => {
            if (reply?.error) reject(new Error(reply.error));
            else resolve(reply);
        });
    });
}

export async function slice({ objects, process = {} } = {}) {
    if (!objects?.length) throw new Error('Nothing to slice');
    const widgets = objects.map(object => {
        const floats = toFloats(object.vertices);
        const { min, max } = bounds(floats);
        const widget = newWidget();
        widget.loadVertices(floats).center();
        // widget positions are relative to the bed centre
        widget.move(
            (min[0] + max[0]) / 2 - device.bedWidth / 2,
            (min[1] + max[1]) / 2 - device.bedDepth / 2,
            0, true);
        widget.anno.extruder = object.tool ?? 0;
        return widget;
    });

    const settings = {
        mode: 'FDM',
        controller: {},
        render: false,
        filter: { FDM: 'internal' },
        device: { ...structuredClone(conf.defaults.fdm.d), ...structuredClone(device) },
        process: { ...structuredClone(conf.defaults.fdm.p), ...baseProcess, ...process },
        widget: Object.fromEntries(widgets.map(w => [w.id, {}])),
        time: Date.now(),
    };

    client.clear();
    client.sync(widgets);
    client.rotate(settings);
    await new Promise(resolve => client.slicePre(settings, resolve));
    for (const [i, widget] of widgets.entries()) {
        await new Promise((resolve, reject) => {
            client.slice(settings, widget, msg => {
                if (msg.error) reject(new Error(msg.error));
                if (typeof msg.update === 'number') {
                    post({ progress: 0.6 * (i + msg.update) / widgets.length, phase: 'slice' });
                }
                if (msg.done) resolve();
            });
        });
    }
    await new Promise(resolve => client.slicePost(settings, resolve));
    await new Promise(resolve => client.prepare(settings,
        progress => post({ progress: 0.6 + 0.3 * (progress || 0), phase: 'prepare' }),
        resolve));
    const output = [];
    await new Promise(resolve => client.export(settings, segment => {
        if (typeof segment === 'string') output.push(segment);
    }, resolve));
    post({ progress: 1, phase: 'done' });

    const gcode = output.join('\n');
    checkBounds(gcode);
    return { gcode, ...stats(gcode) };
}

// Refuse G-code that would move outside the printable area. Start/end macros
// run inside the firmware, so only explicit coordinates are checked here.
export function checkBounds(gcode) {
    const { bedWidth, bedDepth, maxHeight } = device;
    const limits = { X: [0, bedWidth], Y: [0, bedDepth], Z: [0, maxHeight] };
    let lineNo = 0;
    for (const line of gcode.split(/\r?\n/)) {
        lineNo++;
        if (!/^G[0-3]\s/.test(line)) continue;
        for (const [, axis, value] of line.split(';')[0].matchAll(/([XYZ])(-?[\d.]+)/g)) {
            const [min, max] = limits[axis];
            const v = Number(value);
            if (v < min || v > max) {
                throw new Error(`G-code leaves the bed at line ${lineNo}: ${line.trim()} (${axis} must be ${min}..${max})`);
            }
        }
    }
}

self.snarwal = { version, loadModel, slice, device: { bedWidth: device.bedWidth, bedDepth: device.bedDepth, maxHeight: device.maxHeight, tools: device.extruders.length } };
post({ ready: version });
