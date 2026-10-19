// Builds the offline slicing bundle that the iOS app loads into a hidden WKWebView.
//
// Output (engine/dist/):
//   index.html            entry page, exposes window.snarwal
//   snarwal-engine.js     bridge + Kiri:Moto engine
//   kiri/worker.js        Kiri slicing worker (module worker)
//   kiri/pool.js          Kiri minion worker (module worker)
//   wasm/*.wasm           geometry kernels fetched at runtime
//
// Kiri:Moto lives in vendor/grid-apps (git submodule, pinned). Only its FDM
// engine path is bundled; the LGPL planegcs solver (void modeler) is not.

import { build } from 'esbuild';
import { execSync } from 'node:child_process';
import fs from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const kiri = path.resolve(here, '../vendor/grid-apps');
const dist = path.join(here, 'dist');
const prod = process.argv.includes('--prod');

function run(cmd, cwd) {
    console.log(`$ ${cmd}`);
    execSync(cmd, { cwd, stdio: 'inherit' });
}

async function prepareKiri() {
    if (!existsSync(path.join(kiri, 'package.json'))) {
        throw new Error('vendor/grid-apps missing, run: git submodule update --init');
    }
    if (!existsSync(path.join(kiri, 'node_modules'))) {
        // --ignore-scripts skips electron and other desktop-only postinstalls
        run('npm install --ignore-scripts --no-audit --no-fund', kiri);
    }
    // third-party ESM wrappers that Kiri generates with webpack
    const generated = {
        'src/ext/three.js': 'bin/webpack-three-esm.js',
        'src/ext/jszip-esm.js': 'bin/webpack-jszip-esm.js',
        'src/ext/quickjs.js': 'bin/webpack-quickjs-esm.js',
    };
    for (const [out, config] of Object.entries(generated)) {
        if (!existsSync(path.join(kiri, out))) {
            run(`npx webpack --config ${config}`, kiri);
        }
    }
    // Kiri imports its device catalog from src/pack/kiri-devs.js
    const root = path.join(kiri, 'src/kiri/dev');
    const devices = {};
    for (const type of await fs.readdir(root)) {
        devices[type] = {};
        for (const file of await fs.readdir(path.join(root, type))) {
            const name = file.replace(/\.json$/, '');
            devices[type][name] = JSON.parse(await fs.readFile(path.join(root, type, file), 'utf8'));
        }
    }
    await fs.mkdir(path.join(kiri, 'src/pack'), { recursive: true });
    await fs.writeFile(path.join(kiri, 'src/pack/kiri-devs.js'), `export const devices = ${JSON.stringify(devices)};`);
}

async function bundle() {
    await fs.rm(dist, { recursive: true, force: true });
    const common = {
        bundle: true,
        format: 'esm',
        platform: 'browser',
        target: 'es2022',
        minify: prod,
        sourcemap: false,
        define: { 'process.env.NODE_ENV': prod ? '"prod"' : '"dev"' },
        // same list as Kiri's own bin/esbuild.config.mjs: dead require()s in src/ext/jspoly.js
        external: [
            'module', 'node:module', './constants', './voronoi_structures', './voronoi_ctypes',
            '../thirdparty/jsbn', './collections', './voronoi_predicates', './voronoi_builder',
            './point_data', './segment_data', './cppgen', './voronoi_diagram', './voronoi',
        ],
        logOverride: {
            'duplicate-class-member': 'silent',
            'duplicate-object-key': 'silent',
            'direct-eval': 'silent',
        },
    };
    await build({ ...common, entryPoints: [path.join(here, 'src/snarwal-engine.js')], outfile: path.join(dist, 'snarwal-engine.js') });
    await build({ ...common, entryPoints: [path.join(kiri, 'src/kiri/run/worker.js')], outfile: path.join(dist, 'kiri/worker.js') });
    await build({ ...common, entryPoints: [path.join(kiri, 'src/kiri/run/minion.js')], outfile: path.join(dist, 'kiri/pool.js') });

    await fs.mkdir(path.join(dist, 'wasm'), { recursive: true });
    await fs.copyFile(path.join(kiri, 'src/wasm/kiri-geo.wasm'), path.join(dist, 'wasm/kiri-geo.wasm'));
    await fs.copyFile(path.join(kiri, 'node_modules/manifold-3d/manifold.wasm'), path.join(dist, 'wasm/manifold.wasm'));
    await fs.copyFile(path.join(here, 'web/index.html'), path.join(dist, 'index.html'));
    await fs.copyFile(path.join(kiri, 'license.md'), path.join(dist, 'KIRI-LICENSE.md'));
}

await prepareKiri();
await bundle();
console.log(`engine bundle written to ${path.relative(process.cwd(), dist) || '.'}`);
