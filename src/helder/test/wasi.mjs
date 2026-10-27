// A test program built for wasm32-wasi, under node (`helder test --target
// wasm`): node's WASI with the working directory preopened as itself (the
// snapshots, files tests read), the environment passed on, and
// helder.async's imports (src/helder/async/imports.mjs: the loop turned by
// node's, as in the browser), with the small part of browser.mjs's host they
// use. The program exits through proc_exit, after main returned too.
//   node --stack-size=65500 src/helder/test/wasi.mjs <module.wasm> [args...]
import fs from 'node:fs';
import process from 'node:process';
import { WASI } from 'node:wasi';
import asyncImports from '../async/imports.mjs';

const [file, ...args] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [file, ...args], env: process.env, preopens: { '.': '.' }, returnOnExit: true });
let exports = null;
const objects = [null], free = [];
const host = {
	options: {},
	memory: () => exports.memory,
	bytes: (p, n) => new Uint8Array(exports.memory.buffer, p, n),
	string(p) {
		const m = new Uint8Array(exports.memory.buffer);
		let e = p;
		while (m[e]) e++;
		return new TextDecoder().decode(m.subarray(p, e));
	},
	handles: {
		add(o) {
			const h = free.length ? free.pop() : objects.length;
			objects[h] = o;
			return h;
		},
		get: (h) => objects[h],
		size: () => objects.length,
		remove(h) {
			objects[h] = null;
			free.push(h);
		},
	},
	call: (f, ...a) => exports.__indirect_function_table.get(f)(...a),
	onDispose() {},
};
const imports = { ...wasi.getImportObject(), ...asyncImports(host) };
// (an exit from a callback, after main returned: node's WASI only returns from start)
imports.wasi_snapshot_preview1 = { ...imports.wasi_snapshot_preview1, proc_exit: (code) => process.exit(code) };
const module = await WebAssembly.compile(fs.readFileSync(file));
const wanted = new Set(WebAssembly.Module.imports(module).map((i) => i.module));
for (const m of Object.keys(imports)) if (!wanted.has(m)) delete imports[m];
const instance = await WebAssembly.instantiate(module, imports);
exports = instance.exports;
const code = wasi.start(instance);
if (code) process.exit(code);
