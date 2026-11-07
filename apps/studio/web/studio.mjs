// helder studio in the browser: the page's side of apps/studio built for
// the web (studio.wasm, helder's web target on WebGPU or WebGL2). The
// studio's own module draws the whole page (its canvas); this module
// keeps what a page has and the module does not:
//
// - Projects live in the origin's private file system (OPFS), each under
//   projects/<name>/ (its files as written), its preview beside them in
//   projects/<name>/.studio/ (preview.wasm, project.json: the links and
//   live literals' tables its build wrote). The page reads the project's
//   files into memory before the module starts and serves them to it
//   (Files: studio_web's fs_*); a file the studio writes is written back
//   to OPFS at once, and to the folder it was opened from when the page may
//   write there (the File System Access API's handle, kept in IndexedDB).
// - Opening: ?project=<name> opens an OPFS project; without it the studio
//   shows its welcome (Welcome.hx): a folder picked (showDirectoryPicker:
//   its sources copied into OPFS) or an example bundled with the page
//   (examples/<name>/project.json and preview.wasm, as `helder studio
//   <project> -- --export-web` writes them; examples/index.json lists them)
//   is put in OPFS and the page opens it.
// - The preview host: the project's program in a Web Worker
//   (helder/story/web/worker.mjs), every screen in it, each frame an
//   ImageBitmap posted here and handed to the module as a browser image
//   (gfx's helder_image handle: the studio's renderer uploads it,
//   copyExternalImageToTexture, and composites it as any image). The
//   devtools protocol's lines go both ways as the worker's messages.
// - The compiler: helder.compiler.service as wasm in its own worker, when
//   the page has one (compiler/worker.mjs): its requests relayed (not yet).
//
// ?gfx=webgl2 takes WebGL2 even where WebGPU is. window.studioWeb exposes
// the page's state to checks (tests/studio-web): the studio's events (its
// log: first frame, all shown, selected, patched, shown...), the preview's
// frames, the worker's start.
import { run } from './helder/os/browser.mjs';

const params = new URLSearchParams(location.search);
const gfx = params.get('gfx') ?? undefined;
const enc = new TextEncoder(), dec = new TextDecoder();
const state = (window.studioWeb = { events: [], frames: 0, framesByScreen: {}, logs: [], started: null, project: null, ready: false, error: null });
const t0 = performance.now();

// ---- OPFS

const root = await navigator.storage.getDirectory();
async function dirAt(path, create = false) {
	let d = root;
	for (const p of path.split('/').filter(Boolean)) d = await d.getDirectoryHandle(p, { create });
	return d;
}
async function writeFile(path, data) {
	const parts = path.split('/').filter(Boolean), name = parts.pop();
	const d = await dirAt(parts.join('/'), true);
	const w = await (await d.getFileHandle(name, { create: true })).createWritable();
	await w.write(data);
	await w.close();
}
async function readTree(d, prefix, out) {
	for await (const [name, h] of d.entries()) {
		if (h.kind === 'directory') {
			if (name.startsWith('.') || name === 'bin' || name === 'node_modules') continue;
			out.dirs.add(prefix + name);
			await readTree(h, prefix + name + '/', out);
		} else out.files.set(prefix + name, await (await h.getFile()).text());
	}
}
async function projectNames() {
	const out = [];
	try {
		for await (const [name, h] of (await dirAt('projects')).entries()) if (h.kind === 'directory') out.push(name);
	} catch {}
	return out.sort();
}

// (a folder's handle, kept in IndexedDB: the folder written through to)
function idb() {
	return new Promise((resolve, reject) => {
		const r = indexedDB.open('helder-studio', 1);
		r.onupgradeneeded = () => r.result.createObjectStore('folders');
		r.onsuccess = () => resolve(r.result);
		r.onerror = () => reject(r.error);
	});
}
async function folderOf(name, handle) {
	const db = await idb();
	return new Promise((resolve) => {
		const t = db.transaction('folders', handle ? 'readwrite' : 'readonly'), s = t.objectStore('folders');
		const r = handle ? s.put(handle, name) : s.get(name);
		r.onsuccess = () => resolve(handle ?? r.result ?? null);
		r.onerror = () => resolve(null);
	});
}

// ---- opening

const examples = await fetch('examples/index.json').then((r) => (r.ok ? r.json() : []), () => []);

async function openExample(name) {
	const base = `examples/${name}/`;
	const [meta, wasm] = await Promise.all([fetch(base + 'project.json').then((r) => r.json()), fetch(base + 'preview.wasm').then((r) => (r.ok ? r.arrayBuffer() : null))]);
	try {
		await root.removeEntry('projects/' + name, { recursive: true });
	} catch {}
	try {
		await (await dirAt('projects')).removeEntry(name, { recursive: true });
	} catch {}
	for (const [p, text] of Object.entries(meta.files)) await writeFile(`projects/${name}/${p}`, text);
	const { files, ...rest } = meta;
	await writeFile(`projects/${name}/.studio/project.json`, JSON.stringify(rest));
	if (wasm) await writeFile(`projects/${name}/.studio/preview.wasm`, wasm);
	go(name);
}

async function openFolder() {
	let handle;
	try {
		handle = await showDirectoryPicker({ id: 'helder-studio', mode: 'readwrite' });
	} catch (e) {
		return log('studio: no folder (' + e.message + ')');
	}
	const name = handle.name.replace(/[^A-Za-z0-9._-]+/g, '-');
	const copy = async (d, prefix) => {
		for await (const [n, h] of d.entries()) {
			if (n.startsWith('.') || n === 'bin' || n === 'node_modules') continue;
			if (h.kind === 'directory') await copy(h, prefix + n + '/');
			else if (/\.(hx|tsx?|json|md|hxml|txt|css|svg)$/.test(n)) await writeFile(`projects/${name}/${prefix}${n}`, await (await h.getFile()).text());
		}
	};
	await copy(handle, '');
	await folderOf(name, handle);
	go(name);
}

function go(name) {
	const u = new URL(location.href);
	u.searchParams.set('project', name);
	location.href = u.href;
}

// ---- the project

const projectName = params.get('project');
const files = new Map(), dirs = new Set();
let meta = null, previewBytes = null, folder = null;
if (projectName) {
	try {
		const d = await dirAt('projects/' + projectName);
		const out = { files: new Map(), dirs: new Set() };
		await readTree(d, '', out);
		const dir = '/projects/' + projectName;
		dirs.add('/projects');
		dirs.add(dir);
		for (const p of out.dirs) dirs.add(dir + '/' + p);
		for (const [p, t] of out.files) files.set(dir + '/' + p, t);
		try {
			const s = await dirAt(`projects/${projectName}/.studio`);
			meta = JSON.parse(await (await (await s.getFileHandle('project.json')).getFile()).text());
			previewBytes = await (await (await s.getFileHandle('preview.wasm')).getFile()).arrayBuffer();
		} catch {}
		folder = await folderOf(projectName).catch(() => null);
		state.project = projectName;
	} catch (e) {
		state.error = `no project ${projectName} (${e.message})`;
	}
}
const dir = projectName ? '/projects/' + projectName : null;

function project() {
	if (!dir || state.error) return null;
	// (the build's paths to the project's: its links, and every file of the directory it was built in)
	const links = {};
	if (meta) {
		for (const [built, rel] of Object.entries(meta.links ?? {})) links[built] = dir + '/' + rel;
		for (const f of files.keys()) links[meta.root + f.slice(dir.length)] = f;
	}
	return { dir, name: meta?.name ?? projectName, links, tables: meta?.tables ?? [], preview: !!previewBytes };
}

const writes = [];
function saveFile(path, text) {
	files.set(path, text);
	if (!dir || !path.startsWith(dir + '/')) return;
	const rel = path.slice(dir.length + 1);
	// (in order: OPFS, then the folder it came from when the page may write there)
	const p = (writes[writes.length - 1] ?? Promise.resolve()).then(async () => {
		await writeFile(`projects/${projectName}/${rel}`, text);
		if (folder && (await folder.queryPermission?.({ mode: 'readwrite' })) === 'granted') {
			const parts = rel.split('/'), n = parts.pop();
			let d = folder;
			for (const x of parts) d = await d.getDirectoryHandle(x, { create: true });
			const w = await (await d.getFileHandle(n, { create: true })).createWritable();
			await w.write(text);
			await w.close();
		}
	}).catch((e) => log('studio: ' + rel + ' not saved: ' + e.message));
	writes.push(p);
	state.saved = () => Promise.all(writes);
}

function log(s) {
	state.logs.push(s);
	console.log(s);
}

// ---- the preview host's worker

const preview = { worker: null, events: [] };
const fontFiles = ['fonts/DejaVuSans.ttf', 'fonts/DejaVuSans-Bold.ttf'];
const previewFonts = Promise.all(fontFiles.map((u) => fetch(u).then((r) => (r.ok ? r.arrayBuffer() : null), () => null))).then((l) => l.filter(Boolean));

function startPreview(host) {
	if (!previewBytes || !meta) return 0;
	const w = new Worker(new URL('helder/story/web/worker.mjs', location.href), { type: 'module' });
	preview.worker = w;
	w.onmessage = (e) => {
		const m = e.data;
		switch (m.type) {
			case 'frame': {
				const h = host.handles.add({ file: null, premultiply: true, state: 1, width: m.bitmap.width, height: m.bitmap.height, bitmap: m.bitmap, decoding: null });
				state.frames++;
				state.framesByScreen[m.screen] = (state.framesByScreen[m.screen] ?? 0) + 1;
				preview.events.push([2, m.screen, h, m.width, m.height, m.version]);
				break;
			}
			case 'line':
				preview.events.push([1, host.handles.add(m.line)]);
				break;
			case 'log':
				preview.events.push([3, host.handles.add(m.text)]);
				break;
			case 'exit':
				log('studio: the preview ended: ' + m.code + ' ' + (m.stack ?? ''));
				preview.events.push([4, m.code]);
				break;
			case 'snapshot':
				preview.snapshot?.(m.snapshot);
				preview.snapshot = null;
				break;
			case 'stats':
				preview.stats?.(m);
				preview.stats = null;
				break;
			case 'started':
				state.started = { ms: m.ms, backend: m.backend, at: performance.now() - t0 };
				preview.events.push([5, Math.round(m.ms)]);
				break;
		}
		host.wake?.(0);
	};
	w.onerror = (e) => log('studio: the preview\'s worker: ' + e.message);
	previewFonts.then(async (fonts) => {
		const module = await WebAssembly.compile(previewBytes);
		w.postMessage({ type: 'start', wasm: module, imports: (meta.imports ?? []).map((p) => new URL(`helder/${p}/imports.mjs`, location.href).href), fonts, gfx });
	});
	return 1;
}

// ---- the compiler's worker (helder.compiler.web: its protocol's client), when the site has one

let compiler = null;
async function compilerClient() {
	if (compiler !== null) return compiler;
	compiler = false;
	try {
		const r = await fetch('helder/compiler/web/worker.mjs', { method: 'HEAD' });
		if (!r.ok) return compiler;
		const { CompilerClient } = await import('./helder/compiler/web/client.mjs');
		const c = new CompilerClient(new Worker(new URL('helder/compiler/web/worker.mjs', location.href), { type: 'module' }));
		c.onLog = (t) => log('[compiler] ' + t);
		await c.init();
		compiler = c;
	} catch (e) {
		log('studio: no compiler: ' + e.message);
	}
	state.compiler = !!compiler;
	return compiler;
}
if (projectName) compilerClient();

// a build of the preview (the request: {entry, args}): the project's files
// written to the compiler at their paths, built, the preview started again
// from the running one's state (its snapshot); the answer as event 6
let compiles = 0;
function compile(host, req) {
	const id = ++compiles;
	const answer = (r) => {
		preview.events.push([6, id, host.handles.add(JSON.stringify(r))]);
		host.wake?.(0);
	};
	(async () => {
		const c = await compilerClient();
		if (!c) return answer({ ok: false, why: 'no compiler' });
		await c.write(Object.fromEntries([...files].filter(([k]) => k.startsWith(dir + '/'))));
		const b = await c.build(req.entry, { dev: true, args: req.args });
		if (b.ok && b.wasm) {
			previewBytes = b.wasm;
			const snapshot = await new Promise((resolve) => {
				if (!preview.worker) return resolve(null);
				preview.snapshot = resolve;
				preview.worker.postMessage({ type: 'snapshot' });
				setTimeout(() => resolve(null), 3000);
			});
			preview.worker.postMessage({ type: 'start', wasm: await WebAssembly.compile(previewBytes), imports: (meta.imports ?? []).map((p) => new URL(`helder/${p}/imports.mjs`, location.href).href),
				fonts: await previewFonts, gfx, snapshot });
		}
		answer({ ok: b.ok, diagnostics: b.diagnostics, messages: b.messages, ms: b.ms });
	})().catch((e) => answer({ ok: false, why: String(e?.message ?? e) }));
	return id;
}

// ---- the module's imports (studio_web)

function studioWeb(host) {
	const text = (s) => (s == null ? 0 : host.handles.add(String(s)));
	const str = (p) => host.string(p);
	const exists = (p) => (files.has(p) ? 1 : dirs.has(p.replace(/\/$/, '')) ? 2 : 0);
	return {
		studio_web: {
			fs_read: (p) => text(files.get(str(p))),
			fs_write: (p, t) => saveFile(str(p), str(t)),
			fs_exists: (p) => exists(str(p)),
			fs_list(p) {
				const d = str(p).replace(/\/$/, '');
				if (!dirs.has(d)) return 0;
				const names = new Set();
				for (const k of [...files.keys(), ...dirs]) if (k.startsWith(d + '/')) names.add(k.slice(d.length + 1).split('/')[0]);
				return text(JSON.stringify([...names].sort()));
			},
			project: () => {
				const p = project();
				return p ? text(JSON.stringify(p)) : 0;
			},
			examples: () => text(JSON.stringify(examples)),
			projects: () => text(JSON.stringify([])),
			open_folder: () => void openFolder(),
			open_example: (n) => void openExample(str(n)),
			open_project: (n) => go(str(n)),
			preview_start: () => startPreview(host),
			preview_send: (p) => preview.worker?.postMessage({ type: 'line', line: str(p) }),
			preview_next(ev) {
				const e = preview.events.shift();
				if (!e) return 0;
				const v = new DataView(host.memory().buffer);
				for (let i = 1; i < e.length; i++) v.setInt32(ev + 4 * (i - 1), e[i] | 0, true);
				return e[0];
			},
			frame_release(h) {
				const im = host.handles.get(h);
				im?.bitmap?.close();
				if (im) host.handles.remove(h);
			},
			compile: (p) => (compiler === false ? 0 : compile(host, JSON.parse(str(p)))),
			event(p) {
				const e = JSON.parse(str(p));
				e.ms_page = Math.round(performance.now() - t0);
				state.events.push(e);
			},
			text_length: (h) => enc.encode(host.handles.get(h)).length,
			text_take(h, p) {
				const b = enc.encode(host.handles.get(h));
				host.bytes(p, b.length + 1).set(b);
				host.bytes(p + b.length, 1)[0] = 0;
				host.handles.remove(h);
			},
		},
	};
}

// (the welcome's lists: OPFS's projects read before the module starts)
const opfsProjects = await projectNames();
function withProjects(host) {
	const i = studioWeb(host);
	i.studio_web.projects = () => host.handles.add(JSON.stringify(opfsProjects.map((name) => ({ name }))));
	return i;
}

// (the studio's fonts for the browser's own text fields over the canvas: its native editors)
for (const [family, file, weight] of [['Hanken Grotesk', 'HankenGrotesk-Regular.ttf', '400'], ['Hanken Grotesk', 'HankenGrotesk-Medium.ttf', '500'], ['Geist Mono', 'GeistMono-Regular.ttf', '400']])
	document.fonts.add(new FontFace(family, `url(fonts/${file})`, { weight }));
await document.fonts.load('13px "Hanken Grotesk"').catch(() => {});

const IMPORTS = (window.STUDIO_IMPORTS ?? []).map((p) => `./helder/${p}/imports.mjs`);
const fonts = await Promise.all(fontFiles.map((u) => fetch(u).then((r) => (r.ok ? r.arrayBuffer() : null), () => null))).then((l) => l.filter(Boolean));
try {
	const r = await run(window.STUDIO_WASM ?? 'studio.wasm', {
		imports: [...IMPORTS, withProjects], canvas: 'studio', fonts, gfx, args: [],
		stdout: (s) => log(s), stderr: (s) => log('stderr: ' + s),
		onExit: (code, stack) => log('studio: exit ' + code + ' ' + (stack ?? '')),
		onError: (e) => log('studio: ' + e.message),
	});
	state.host = r.host;
	// (the memory a check reads: the studio's module, the preview's, the page's JavaScript)
	state.stats = () => new Promise((resolve) => {
		const studio = r.host.memory().buffer.byteLength, js = performance.memory?.usedJSHeapSize ?? 0;
		if (!preview.worker) return resolve({ studio, preview: 0, js });
		preview.stats = (m) => resolve({ studio, preview: m.memory, js });
		preview.worker.postMessage({ type: 'stats' });
	});
	state.ready = true;
	state.backend = r.host.gfx?.backend ?? null;
} catch (e) {
	state.error = String(e?.stack ?? e);
	log('studio: ' + state.error);
}
