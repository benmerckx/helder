// The landing page's builds, in node: each example of bin/landing's
// manifest compiled for wasm32-wasi as the page compiles it (wasi.js over the
// packs), and the first one for every native target.
//
//   node landing/test.mjs [site dir] [example id ...]
import fs from 'node:fs';
import path from 'node:path';
import v8 from 'node:v8';
import { compile } from './compile.js';
import { MemFS, unpack } from './wasi.js';

v8.setFlagsFromString('--experimental-wasm-exnref');
const dir = path.resolve(process.argv[2] ?? 'bin/landing');
const only = process.argv.slice(3);
const read = (f) => fs.readFileSync(path.join(dir, f));
const manifest = JSON.parse(read('manifest.json'));
const module = await WebAssembly.compile(read('haxe.wasm'));
const memfs = new MemFS();
for (const [f, at] of [['std.pack', '/lib'], ['src.pack', '/lib/src']]) memfs.mount(at, unpack(read(f)));

let failed = 0;
async function check(example, target) {
	if (target !== 'wasm32-wasi') memfs.mount('/lib/rt', unpack(read(`rt/${target}.pack`)));
	let opened = 0;
	const r = await compile({ module, fs: memfs, example, target, onOpen: () => opened++ });
	const what = `${example.id.padEnd(20)} ${target.padEnd(15)}`;
	if (r.ok) console.log(`${what} ok ${(r.ms / 1000).toFixed(1).padStart(5)}s ${String(r.bytes.length).padStart(9)} B  ${opened} files`);
	else {
		failed++;
		console.log(`${what} FAILED\n${r.log.join('\n')}`);
	}
}

const examples = manifest.examples.filter((e) => !only.length || only.includes(e.id));
for (const e of examples) await check(e, 'wasm32-wasi');
for (const t of manifest.targets) await check(examples[0], t);
if (failed) {
	console.log(`landing: ${failed} builds failed`);
	process.exit(1);
}
