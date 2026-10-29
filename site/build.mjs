// The site (bun run site): one page listing the examples, written by
// site/index.tsx (TSX, helder's TypeScript frontend, rendered by
// helder.web's static renderer), each example that runs in a browser a
// WebAssembly island started by its Play button.
//
//   node site/build.mjs [out]      (default bin/site)
//
// 1. the examples: each directory's programs with a header (as tests/Run.hx's
//    examples lane reads them: `// title:`, `// summary:`, `// tags:`,
//    `// demo:`), a .hx file or a TypeScript directory's main.ts(x);
// 2. those whose demo is `canvas WxH` or `sound` built for the web
//    (`helder build <entry> --target web`, one build each), into
//    bin/site-build/<id>/;
// 3. <out>: examples/<id>/ (each one's module and assets), helder/ (the
//    packages' browser modules, all the builds' together), fonts/,
//    loader.js (helder.web's island loader);
// 4. bin/site-build/examples.json, which index.tsx imports, then the page
//    built (natively) and run: <out>/index.html.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const out = process.argv[2] ?? 'bin/site';
const work = 'bin/site-build';
const cli = ['src/helder/cli/run.mjs'];
const REPO = 'https://github.com/benmerckx/universe';

// (apk: android, an example built for Android phones too, with SITE_APK=1: its APK beside the page, linked from its card)
const HEADER = /^\/\/ *(title|summary|tags|demo|apk): *(.*)$/;

function header(file) {
	const head = {};
	for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
		if (!line.startsWith('//')) break;
		const m = HEADER.exec(line.trim());
		if (m) head[m[1]] = m[2].trim();
	}
	return head.title ? head : null;
}

// demo: canvas WxH (a canvas of that size), sound (no canvas: a click starts
// the audio); island and module are helder.web's, not a program to start
function demoOf(s) {
	const c = /^canvas (\d+)x(\d+)$/.exec(s ?? '');
	if (c) return { kind: 'canvas', width: +c[1], height: +c[2] };
	if (s === 'sound') return { kind: 'sound', width: 0, height: 0 };
	return null;
}

// the examples, by directory (their ids as tests/Run.hx's examples lane names them)
function examples() {
	const list = [];
	for (const dir of fs.readdirSync('examples').sort()) {
		const p = `examples/${dir}`;
		if (!fs.statSync(p).isDirectory()) continue;
		const hx = fs.readdirSync(p).filter((f) => f.endsWith('.hx')).sort();
		const ts = ['main.ts', 'main.tsx'].find((f) => fs.existsSync(`${p}/${f}`));
		const entries = ts ? [{ file: `${p}/${ts}`, entry: p, main: 'main', id: dir }]
			: hx.map((f) => {
				const main = f.slice(0, -3);
				return { file: `${p}/${f}`, entry: `${p}/${f}`, main, id: dir + (hx.length > 1 && main.toLowerCase() !== dir.replace('-', '') ? '-' + main.toLowerCase() : '') };
			});
		for (const e of entries) {
			const head = header(e.file);
			if (!head) continue;
			list.push({ ...e, dir, title: head.title, summary: head.summary ?? '', tags: (head.tags ?? '').split(',').map((t) => t.trim()).filter((t) => t),
				demo: demoOf(head.demo), apk: head.apk === 'android' });
		}
	}
	return list;
}

function run(args, log) {
	return new Promise((resolve) => {
		const p = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
		let text = '';
		p.stdout.on('data', (d) => (text += d));
		p.stderr.on('data', (d) => (text += d));
		p.on('close', (code) => {
			if (log) fs.writeFileSync(log, text);
			resolve({ code, text });
		});
	});
}

function copyDir(from, to) {
	fs.mkdirSync(to, { recursive: true });
	fs.cpSync(from, to, { recursive: true });
}

const t0 = Date.now();
const all = examples();
const builds = all.filter((e) => e.demo);
fs.rmSync(work, { recursive: true, force: true });
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });

// (the CLI built once, before the builds run it in parallel)
const help = spawnSync(process.execPath, [...cli, 'help'], { encoding: 'utf8' });
if (help.status !== 0) {
	process.stderr.write(help.stdout + help.stderr);
	process.exit(1);
}

const failed = [];
let next = 0;
async function worker() {
	while (next < builds.length) {
		const e = builds[next++];
		const dir = `${work}/${e.id}`;
		fs.mkdirSync(dir, { recursive: true });
		const s = Date.now();
		const r = await run([...cli, 'build', e.entry, '--target', 'web', '-o', `${dir}/${e.main}.wasm`], `${dir}.log`);
		const ok = r.code === 0 && fs.existsSync(`${dir}/${e.main}.wasm`);
		console.log(`${e.id.padEnd(22)} ${ok ? 'ok  ' : 'FAIL'} ${((Date.now() - s) / 1000).toFixed(1).padStart(6)}s`);
		if (!ok) {
			failed.push(e.id);
			console.log(r.text.slice(-1500));
		}
	}
}
await Promise.all(Array.from({ length: Math.max(1, Math.min(4, os.availableParallelism() - 1)) }, worker));
if (failed.length) {
	console.error(`site: ${failed.join(', ')} failed to build`);
	process.exit(1);
}

// the layout: each build's module and assets, the browser modules and fonts shared
const site = [];
for (const e of all) {
	const item = { id: e.id, title: e.title, summary: e.summary, tags: e.tags, source: `${REPO}/tree/main/examples/${e.dir}`,
		demo: e.demo, wasm: '', imports: [], fonts: [], assets: '', apk: null };
	if (e.apk && process.env.SITE_APK) {
		// (arm64, a phone's; signed with the key HELDER_ANDROID_KEY names when it is set, else helder's cached one)
		const file = `apk/${e.id}.apk`;
		fs.mkdirSync(`${out}/apk`, { recursive: true });
		const r = await run([...cli, 'build', e.entry, '--target', 'android', '-o', `${out}/${file}`], `${work}/${e.id}-apk.log`);
		if (r.code !== 0 || !fs.existsSync(`${out}/${file}`)) {
			console.error(`site: ${e.id}'s APK failed to build\n` + r.text.slice(-1500));
			process.exit(1);
		}
		const commit = (process.env.GITHUB_SHA ?? spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout ?? '').trim().slice(0, 7);
		item.apk = { file, bytes: fs.statSync(`${out}/${file}`).size, commit };
		console.log(`${(e.id + ' (apk)').padEnd(22)} ok   ${(item.apk.bytes / 1048576).toFixed(1)} MB`);
	}
	if (e.demo) {
		const dir = `${work}/${e.id}`, dest = `${out}/examples/${e.id}`;
		fs.mkdirSync(dest, { recursive: true });
		fs.copyFileSync(`${dir}/${e.main}.wasm`, `${dest}/${e.main}.wasm`);
		item.wasm = `examples/${e.id}/${e.main}.wasm`;
		const listed = `${dir}/${e.main}.wasm.assets.json`;
		if (fs.existsSync(listed) && JSON.parse(fs.readFileSync(listed, 'utf8')).length > 0) {
			fs.copyFileSync(listed, `${dest}/${e.main}.wasm.assets.json`);
			copyDir(`${dir}/assets`, `${dest}/assets`);
			item.assets = `${item.wasm}.assets.json`;
		}
		// (the packages whose browser modules the build put beside it: Page.hx's)
		for (const p of fs.readdirSync(`${dir}/helder`).sort()) {
			copyDir(`${dir}/helder/${p}`, `${out}/helder/${p}`);
			if (fs.existsSync(`${dir}/helder/${p}/imports.mjs`)) item.imports.push(`helder/${p}/imports.mjs`);
		}
		if (fs.existsSync(`${dir}/fonts`)) for (const f of fs.readdirSync(`${dir}/fonts`).sort()) {
			fs.mkdirSync(`${out}/fonts`, { recursive: true });
			fs.copyFileSync(`${dir}/fonts/${f}`, `${out}/fonts/${f}`);
			item.fonts.push(`fonts/${f}`);
		}
	}
	site.push(item);
}
fs.copyFileSync('src/helder/web/loader.js', `${out}/loader.js`);
fs.copyFileSync('site/stage.js', `${out}/stage.js`);
fs.writeFileSync(`${work}/examples.json`, JSON.stringify({ out: `${out}/index.html`, repository: REPO, examples: site }, null, '\t') + '\n');

// the page: index.tsx built natively, then run
const page = await run([...cli, 'build', 'site/index.tsx', '-o', `${work}/page`], `${work}/page.log`);
if (page.code !== 0) {
	console.error(page.text);
	process.exit(1);
}
const r = spawnSync(path.resolve(`${work}/page`), [], { stdio: 'inherit' });
if (r.status !== 0 || !fs.existsSync(`${out}/index.html`)) {
	console.error('site: the page did not write ' + out + '/index.html');
	process.exit(1);
}
console.log(`site: ${out}/index.html, ${site.length} examples (${builds.length} playable), ${((Date.now() - t0) / 1000).toFixed(0)}s`);
