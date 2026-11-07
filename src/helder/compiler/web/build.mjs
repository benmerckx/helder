// Builds helder.compiler.web's toolchain into a directory the page serves
// beside worker.mjs (README.md):
//   node src/helder/compiler/web/build.mjs [out]    (default bin/compiler-web)
//
//   helder-compiler.wasm   helder's compiler (helder.compiler.web.WebMain:
//                          hxmc with helder's hooks and frontends) as
//                          wasm32-wasi, one thread (-D disable-parallelism),
//                          kept in helder's cache per hxmc version and hash
//                          of the compiler's sources, as the native one
//                          (src/helder/compiler/build.mjs)
//   tsc.wasm               TypeScript's API as a wasip1 reactor
//                          (@typescript/typescript-wasip1-wasm, the
//                          typescript package's version; HELDER_TSGO_WASM
//                          names another)
//   sources.bundle         what the compiler and TypeScript read, as the
//                          worker's file system has it under /node_modules:
//                          helder (its package.json, src/), @hxmc/cli
//                          (Haxe's std without the other targets' packages,
//                          hxmc's std), typescript (its package.json, the
//                          API's protocol and enums: helder.typescript's
//                          tables), TypeScript's ECMAScript libraries
//   *.br                   each brotli-compressed (quality 11), for servers
//                          that send them as Content-Encoding: br
//   typescript/            the typescript package's in-process transport
//                          (typescript/wasm and what it imports)
//   manifest.json          the files' sizes, raw and brotli, and versions
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import zlib from 'node:zlib';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = path.resolve(here, '../../..');
const repo = path.resolve(src, '..');
const out = path.resolve(process.argv[2] ?? path.join(repo, 'bin/compiler-web'));
const log = (m) => console.error(m);

function find(rel) {
	for (let d = process.cwd(); ; d = path.dirname(d)) {
		if (fs.existsSync(path.join(d, rel))) return path.join(d, rel);
		if (path.dirname(d) === d) break;
	}
	for (let d = repo; ; d = path.dirname(d)) {
		if (fs.existsSync(path.join(d, rel))) return path.join(d, rel);
		if (path.dirname(d) === d) return null;
	}
}
const cliJson = find('node_modules/@hxmc/cli/package.json');
if (!cliJson) throw new Error('@hxmc/cli is not installed');
const cli = path.dirname(cliJson);
const hxmcVersion = JSON.parse(fs.readFileSync(cliJson, 'utf8')).version;
const tsJson = find('node_modules/typescript/package.json');
if (!tsJson) throw new Error('typescript is not installed');
const typescript = path.dirname(tsJson);
const tsVersion = JSON.parse(fs.readFileSync(tsJson, 'utf8')).version;
const hxmc = spawnSync(process.execPath, [path.join(src, 'helder/compiler/build.mjs'), '--sources'], {encoding: 'utf8'}).stdout.trim();
const cache = process.env.HELDER_CACHE ?? (process.platform === 'win32' ? path.join(process.env.LOCALAPPDATA ?? os.homedir(), 'helder', 'cache')
	: process.platform === 'darwin' ? path.join(os.homedir(), 'Library/Caches/helder') : path.join(process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), '.cache'), 'helder'));

function hashTree(dir, h) {
	for (const e of fs.readdirSync(dir, {withFileTypes: true}).sort((a, b) => a.name < b.name ? -1 : 1)) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) hashTree(p, h);
		else if (e.name.endsWith('.hx')) h.update(e.name).update(fs.readFileSync(p));
	}
	return h;
}

// helder's compiler as wasm32-wasi (legacy exception handling: every browser since 2021)
const key = ['helder/compiler', 'helder/typescript', 'helder/definition', 'helder/gfx/shader', 'helder/dev', 'helder/story', 'helder/jobs', 'helder/asset', 'helder/cli', 'helder/markup']
	.reduce((h, pkg) => fs.existsSync(path.join(src, pkg)) ? hashTree(path.join(src, pkg), h.update(pkg)) : h, crypto.createHash('sha256')).update(hxmcVersion).update(hxmc).update('web').digest('hex').slice(0, 16);
const built = path.join(cache, 'compiler-web', key, 'helder-compiler.wasm');
if (!fs.existsSync(built)) {
	const t0 = Date.now();
	fs.mkdirSync(path.dirname(built), {recursive: true});
	const tmp = `${built}.${process.pid}`;
	log(`building helder's compiler for wasm32-wasi (hxmc ${hxmcVersion})`);
	const b = spawnSync(process.execPath, [path.join(cli, 'hxmc/bootstrap/haxe.mjs'), '-cp', src, '-cp', path.join(hxmc, 'haxe/src'), '-cp', path.join(hxmc, 'hxmc/src'),
		'-main', 'helder.compiler.web.WebMain', '-D', 'disable-parallelism', '-D', 'hih_no_generators', '-D', 'hxmc.target=wasm32-wasi', '-D', 'hxmc.wasm-eh=legacy',
		'--custom-target', `hxmc=${tmp}`], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
	if (b.status !== 0) {
		process.stderr.write(b.stdout + b.stderr);
		process.exit(1);
	}
	fs.renameSync(tmp, built);
	log(`built ${built} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}

// the sources' bundle: a little-endian u32 n, n bytes of UTF-8 JSON
// [[path, size], ...] (paths under /node_modules, sorted), then the files'
// bytes in that order (vfs.mjs's unbundle)
const files = [];
function add(base, rel, at, keep = () => true) {
	const full = path.join(base, rel);
	const st = fs.statSync(full);
	if (st.isDirectory()) {
		for (const e of fs.readdirSync(full).sort()) add(base, path.join(rel, e), at, keep);
	} else if (keep(rel)) files.push([path.posix.join(at, rel.split(path.sep).join('/')), full]);
}
const helderJson = JSON.parse(fs.readFileSync(path.join(repo, 'package.json'), 'utf8'));
files.push(['helder/package.json', path.join(repo, 'package.json')]);
add(src, '', 'helder/src', (rel) => !rel.endsWith('.md') && !rel.includes('.test.') && !rel.endsWith('.snap'));
files.push(['@hxmc/cli/package.json', cliJson]);
const std = path.join(cli, 'haxe/upstream/std');
for (const e of fs.readdirSync(std).sort()) {
	const p = path.join(std, e);
	if (fs.statSync(p).isFile() ? e.endsWith('.hx') : ['haxe', 'sys', 'eval'].includes(e)) add(std, e, '@hxmc/cli/haxe/upstream/std');
}
add(path.join(cli, 'hxmc/bootstrap/hxmc-std'), '', '@hxmc/cli/hxmc/bootstrap/hxmc-std');
files.push(['typescript/package.json', tsJson]);
add(path.join(typescript, 'dist/api/node'), '', 'typescript/dist/api/node', (rel) => rel.endsWith('.js'));
add(path.join(typescript, 'enums'), '', 'typescript/enums', (rel) => rel.endsWith('.js'));
let tsgo = process.env.HELDER_TSGO_WASM;
if (!tsgo) {
	const pkg = find('node_modules/@typescript/typescript-wasip1-wasm/package.json');
	if (!pkg) throw new Error(`@typescript/typescript-wasip1-wasm is not installed (add @typescript/typescript-wasip1-wasm@${tsVersion}, or set HELDER_TSGO_WASM to its lib/tsc.wasm)`);
	const v = JSON.parse(fs.readFileSync(pkg, 'utf8')).version;
	if (v !== tsVersion) throw new Error(`@typescript/typescript-wasip1-wasm ${v} does not match typescript ${tsVersion}`);
	tsgo = path.join(path.dirname(pkg), 'lib/tsc.wasm');
}
add(path.dirname(tsgo), '', '@typescript/typescript-wasip1-wasm/lib', (rel) => /^lib\..*\.d\.ts$/.test(rel) && !/^lib\.(dom|webworker|scripthost)/.test(rel));
files.sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
const datas = files.map(([, f]) => fs.readFileSync(f));
const index = Buffer.from(JSON.stringify(files.map(([p], i) => [p, datas[i].length])));
const head = Buffer.alloc(4);
head.writeUInt32LE(index.length);
const bundle = Buffer.concat([head, index, ...datas]);

fs.mkdirSync(out, {recursive: true});
const manifest = {hxmc: hxmcVersion, typescript: tsVersion, helder: helderJson.version, files: {}};
// (the last build's: a file's .br made again only when its bytes changed)
const last = (() => {
	try {
		return JSON.parse(fs.readFileSync(path.join(out, 'manifest.json'), 'utf8')).files;
	} catch {
		return {};
	}
})();
for (const [name, from] of [['helder-compiler.wasm', built], ['tsc.wasm', tsgo], ['sources.bundle', bundle]]) {
	const to = path.join(out, name);
	fs.rmSync(to, {force: true});
	// (the modules linked where they are when the file system allows: no copy)
	if (typeof from === 'string') try {
		fs.linkSync(from, to);
	} catch {
		fs.copyFileSync(from, to);
	}
	else fs.writeFileSync(to, from);
	const bytes = typeof from === 'string' ? fs.readFileSync(from) : from;
	const sha = crypto.createHash('sha256').update(bytes).digest('hex').slice(0, 16);
	const brPath = path.join(out, name + '.br');
	let brotli = last[name]?.sha === sha && fs.existsSync(brPath) ? fs.statSync(brPath).size : -1;
	if (brotli < 0) {
		const br = zlib.brotliCompressSync(bytes, {params: {[zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: bytes.length, [zlib.constants.BROTLI_PARAM_LGWIN]: 24}});
		fs.writeFileSync(brPath, br);
		brotli = br.length;
	}
	manifest.files[name] = {bytes: bytes.length, brotli, sha};
}
manifest.files['sources.bundle'].count = files.length;
// typescript/wasm's transport and what it imports, beside the worker's (the page needs no node_modules)
for (const rel of ['dist/wasm/index.js', 'dist/wasm/transport.js', 'dist/wasm/wasi.js', 'dist/api/fsCallbacks.js', 'dist/api/node/wtf8.js']) {
	fs.mkdirSync(path.join(out, 'typescript', path.dirname(rel)), {recursive: true});
	fs.copyFileSync(path.join(typescript, rel), path.join(out, 'typescript', rel));
}
// (ES modules, as the typescript package declares them: node imports them from here too)
fs.writeFileSync(path.join(out, 'typescript/package.json'), '{"type": "module"}\n');
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, '\t') + '\n');
console.log(JSON.stringify(manifest));
