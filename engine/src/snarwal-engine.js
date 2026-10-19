// Bridge between the Snarwal app and the Kiri:Moto FDM engine.
//
// The app loads dist/index.html into a hidden WKWebView and calls
//   await snarwal.slice({ stl, process, tool })
// where `stl` is a base64 string or an ArrayBuffer of a binary/ASCII STL.

import { Engine } from '../../vendor/grid-apps/src/kiri/run/engine.js';
import { device, process as baseProcess } from '../profiles/snapmaker-u1.js';

export const version = '0.1.0';

function toArrayBuffer(stl) {
    if (stl instanceof ArrayBuffer) return stl;
    if (ArrayBuffer.isView(stl)) return stl.buffer.slice(stl.byteOffset, stl.byteOffset + stl.byteLength);
    if (typeof stl === 'string') {
        const bin = atob(stl);
        const out = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
        return out.buffer;
    }
    throw new Error('stl must be base64 or ArrayBuffer');
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

const workURL = new URL('kiri/worker.js', location.href).href;
const poolURL = new URL('kiri/pool.js', location.href).href;

export async function slice({ stl, process = {}, tool = 0, onProgress } = {}) {
    const engine = new Engine({ workURL, poolURL });
    if (onProgress) engine.setListener(onProgress);
    engine
        .setDevice(structuredClone(device))
        .setProcess({ ...baseProcess, ...process });
    await engine.parse(toArrayBuffer(stl));
    engine.widget.anno.extruder = tool;
    // widget positions are relative to the bed centre; parse() already centred it
    await engine.slice();
    await engine.prepare();
    const gcode = await engine.export();
    checkBounds(gcode);
    return { gcode, ...stats(gcode) };
}

// Refuse G-code that would move outside the printable area. Start/end macros
// run inside the firmware, so only explicit coordinates are checked here.
function checkBounds(gcode) {
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

self.snarwal = { version, slice };
