// Lean launcher for tshx's wasm32-wasi output: node run-wasi.cjs prog.wasm [args...]
// hxmc/hxmc/bootstrap/wasi.mjs also runs these modules; this one skips its
// compiler-hosting features (Windows paths, brotli stage0, extra imports) so
// process startup stays at plain node's.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const emitWarning = process.emitWarning;
process.emitWarning = (w, ...rest) => { if (!String(w).includes('WASI')) emitWarning.call(process, w, ...rest); };
const { WASI } = require('node:wasi');
const [file, ...args] = process.argv.slice(2);
if (!file) { console.error('usage: node run-wasi.cjs prog.wasm [args...]'); process.exit(2); }
const bytes = fs.readFileSync(file);
let wasm;
try { wasm = new WebAssembly.Module(bytes); }
catch (e) {
	// (exception handling with exnref is behind a flag before node 24)
	require('node:v8').setFlagsFromString('--experimental-wasm-exnref');
	wasm = new WebAssembly.Module(bytes);
}
const wasi = new WASI({ version: 'preview1', args: [path.resolve(file), ...args], env: { ...process.env, PWD: process.cwd() }, preopens: { '/': '/' }, returnOnExit: true });
const imports = wasi.getImportObject();
// Helder's headless runner drives Loop.runUntil synchronously. Its wake import
// needs no host timer; browser builds use Helder's real async host instead.
imports.helder_async = { async_start() {}, async_wake() {} };
process.exitCode = wasi.start(new WebAssembly.Instance(wasm, imports)) ?? 0;
