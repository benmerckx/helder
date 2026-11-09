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
// - Opening: ?project=<name> opens an OPFS project, ?example=<name> a
//   bundled example (its copy in OPFS, made the first time), ?new a new
//   project (new/app.helder, one design file: nothing built, a free name,
//   "project", "project-2"...); without them the studio shows its welcome
//   (Welcome.hx): a new project, a folder picked (showDirectoryPicker:
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
// - Agents: the studio's tools (Tools.hx, the desktop's MCP server's) are
//   called through the module (WebTools: tool_next, tool_done), a
//   snapshot's PNG made here from the GPU's pixels. Where the browser has
//   WebMCP (document.modelContext, earlier navigator.modelContext) they
//   are registered with it, with project.create, project.list and
//   project.open beside them; without it nothing changes.
// - Links: #import=<data> opens files given in the link (JSON, as is or
//   base64url, or z.<base64url of deflate-raw>: {name?, files: {path:
//   text}}) as a new project; #draft=<id> opens a draft of helder.build's
//   relay (/mcp: an agent's) into OPFS and keeps it linked
//   (.studio/draft.json): the agent's patches come over a WebSocket and go
//   through the studio's history, the files written here go back, and
//   after each change the tab reports its check, trees and small PNGs.
//
// - Loading: index.html's loading screen until the studio's first frame
//   (its event: studioLoad.shown), the module's download begun there
//   (STUDIO_WASM, its progress shown).
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

async function freeName(base) {
	const names = await projectNames();
	let name = base;
	for (let n = 2; names.includes(name); n++) name = base + '-' + n;
	return name;
}
const slug = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^[-.]+|-+$/g, '').slice(0, 40);
const newFiles = async () => ({ 'app.helder': await fetch('new/app.helder').then((r) => r.text()) });

// (files from a link or an agent: relative paths, no dot directories, at most 1 MB and 200 files)
function checked(files) {
	if (!files || typeof files !== 'object' || Array.isArray(files)) throw new Error('files: {path: text}');
	const list = Object.entries(files);
	if (list.length > 200) throw new Error('more than 200 files');
	let size = 0;
	for (const [p, t] of list) {
		if (typeof t !== 'string') throw new Error(p + ': not text');
		if (!p || p.length > 200 || p.split('/').some((x) => !x || x.startsWith('.'))) throw new Error(p + ': not a relative path');
		size += enc.encode(t).length;
	}
	if (size > 1 << 20) throw new Error('more than 1 MB');
	return files;
}

async function makeProject(base, files) {
	const name = await freeName(slug(base) || 'project');
	for (const [p, t] of Object.entries(checked(files))) await writeFile(`projects/${name}/${p}`, t);
	return name;
}

async function newProject() {
	go(await makeProject('project', await newFiles()));
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

let leaving = false;
function go(name) {
	leaving = true;
	const u = new URL(location.href);
	u.searchParams.delete('example');
	u.searchParams.delete('new');
	u.searchParams.set('project', name);
	u.hash = '';
	location.href = u.href;
}

// ---- links: #import=<data>, #draft=<id>

const relay = new URL('/mcp/draft/', location.href).href;

async function openImport(data) {
	let json;
	if (data.startsWith('{')) json = data;
	else {
		const z = data.startsWith('z.'), b64 = (z ? data.slice(2) : data).replace(/-/g, '+').replace(/_/g, '/');
		let bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
		if (z) bytes = new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer());
		json = dec.decode(bytes);
	}
	const d = JSON.parse(json);
	go(await makeProject(d.name ?? 'import', d.files));
}

async function openDraft(id) {
	const r = await fetch(relay + encodeURIComponent(id));
	if (!r.ok) throw new Error(r.status === 404 ? 'no such draft (expired?)' : 'the relay: ' + r.status);
	const d = await r.json();
	// (the same draft opened again: its project, its files the draft's)
	const name = (slug(d.name) || 'draft') + '-' + id.slice(0, 6);
	try {
		await (await dirAt('projects')).removeEntry(name, { recursive: true });
	} catch {}
	for (const [p, t] of Object.entries(checked(d.files))) await writeFile(`projects/${name}/${p}`, t);
	await writeFile(`projects/${name}/.studio/draft.json`, JSON.stringify({ id }));
	go(name);
}

{
	const hash = new URLSearchParams(location.hash.slice(1));
	try {
		if (hash.has('draft')) await openDraft(hash.get('draft'));
		else if (hash.has('import')) await openImport(hash.get('import'));
	} catch (e) {
		state.linkError = e.message;
		log('studio: the link: ' + e.message);
		history.replaceState(null, '', location.pathname + location.search);
	}
}

// ---- the project

const projectName = params.get('project');
// (a link's example: the copy already in OPFS when there is one, its edits kept; the welcome's is a fresh copy)
if (!projectName && params.has('example')) {
	const name = params.get('example');
	if ((await projectNames()).includes(name)) go(name);
	else await openExample(name);
} else if (!projectName && params.has('new')) await newProject();
// (on its way to the project: nothing more started here, its fetches cut off by the navigation)
if (leaving) await new Promise(() => {});
const files = new Map(), dirs = new Set();
let meta = null, previewBytes = null, folder = null, draft = null;
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
		try {
			const f = await (await dirAt(`projects/${projectName}/.studio`)).getFileHandle('draft.json');
			draft = { id: JSON.parse(await (await f.getFile()).text()).id };
		} catch {}
		// (a linked draft: its files as the relay has them, an agent's patches made while the tab was closed)
		if (draft) try {
			const r = await fetch(relay + encodeURIComponent(draft.id));
			if (!r.ok) throw new Error(r.status === 404 ? 'expired' : String(r.status));
			for (const [p, t] of Object.entries(checked((await r.json()).files)))
				if (files.get(dir + '/' + p) !== t) {
					files.set(dir + '/' + p, t);
					for (let d = p; d.includes('/'); ) dirs.add(dir + '/' + (d = d.slice(0, d.lastIndexOf('/'))));
					await writeFile(`projects/${projectName}/${p}`, t);
				}
		} catch (e) {
			log('studio: the draft ' + draft.id + ': ' + e.message + ': not linked');
			draft = null;
		}
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
	changed(path);
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
				preview.events.push([2, m.screen, h, m.bitmap.width, m.bitmap.height, m.version]);
				break;
			}
			case 'line':
				preview.events.push([1, host.handles.add(m.line)]);
				break;
			case 'log':
				preview.events.push([3, host.handles.add(m.text)]);
				break;
			case 'exit': {
				log('studio: the preview ended: ' + m.code + ' ' + (m.stack ?? ''));
				// (an incremental build's program that ends right after it starts: built again from cold, a new
				// compiler; the warm server has built a wrong program after some edits, as the desktop studio sees too)
				const last = preview.lastBuild;
				if (m.code !== 0 && last && !last.cold && performance.now() - last.at < 5000) {
					log('studio: the incremental build\'s program ended at its start: building again from cold');
					preview.lastBuild = null;
					compiler?.terminate?.();
					compiler = null;
					compiled.clear();
					compile(host, last.req, true);
					break;
				}
				preview.events.push([4, m.code]);
				break;
			}
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

let compiler = null, starting = null;
// (one start at a time: a build asked while it starts waits for it)
function compilerClient() {
	if (compiler !== null) return compiler;
	return (starting ??= startCompiler().finally(() => (starting = null)));
}
async function startCompiler() {
	let c = false;
	try {
		const r = await fetch('compiler-web/manifest.json', { method: 'HEAD' });
		if (r.ok) {
			const { CompilerClient } = await import('./helder/compiler/web/client.mjs');
			const client = new CompilerClient(new Worker(new URL('helder/compiler/web/worker.mjs', location.href), { type: 'module' }));
			client.onLog = (t) => log('[compiler] ' + t);
			const init = await client.init({ assets: { base: new URL('compiler-web/', location.href).href } });
			state.compilerInit = init.ms;
			c = client;
		}
	} catch (e) {
		log('studio: no compiler: ' + e.message);
	}
	compiler = c;
	state.compiler = !!c;
	return c;
}
// (started at once for code only: design files need no build, and the toolchain is 14 MB to download)
if ([...files.keys()].some((f) => /\.(hx|tsx?)$/.test(f))) compilerClient();

async function importsOf(wasm) {
	const names = [...new Set(WebAssembly.Module.imports(await WebAssembly.compile(wasm)).map((i) => i.module))];
	const out = [];
	for (const p of ['async', 'gfx', 'os', 'text', 'ui', 'image', 'canvas', 'jobs', 'asset']) {
		const s = await fetch(`helder/${p}/imports.mjs`).then((r) => (r.ok ? r.text() : ''), () => '');
		if (names.some((n) => new RegExp('\\b' + n + '\\b').test(s))) out.push(p);
	}
	return out;
}

// a build of the preview (the request: {entry, args}, the project's paths):
// the project's files written to the compiler under /work/<name> (its
// projects' place), built, the preview started again from the running
// one's state (its snapshot); the answer as event 6, with the build's live
// literals' tables (the studio keeps those of its files' contents)
let compiles = 0;
const compiled = new Map();
const work = (p) => (p === dir || p.startsWith(dir + '/') ? '/work/' + projectName + p.slice(dir.length) : p);
const unwork = (p) => (p && (p === '/work/' + projectName || p.startsWith('/work/' + projectName + '/')) ? dir + p.slice(('/work/' + projectName).length) : p);
function compile(host, req, cold = false) {
	const id = ++compiles;
	const answer = (r) => {
		preview.events.push([6, id, host.handles.add(JSON.stringify(r))]);
		host.wake?.(0);
	};
	(async () => {
		const c = await compilerClient();
		if (!c) return answer({ ok: false, why: 'no compiler' });
		// (the files changed since the compiler last had them, told as changed: its server's stamps are not trusted)
		const changed = [...files].filter(([k, v]) => k.startsWith(dir + '/') && compiled.get(k) !== v);
		await c.write(Object.fromEntries(changed.map(([k, v]) => [work(k), v])));
		for (const [k, v] of changed) compiled.set(k, v);
		const b = await c.build(work(req.entry), { dev: true, args: (req.args ?? []).map(work), changed: changed.map(([k]) => work(k)) });
		const tables = [];
		if (b.ok) for (const f of await c.list('/out/.literals').catch(() => [])) {
			if (!f.endsWith('.json')) continue;
			try {
				const t = JSON.parse(dec.decode(await c.read(f)));
				if (t.file?.startsWith('/work/' + projectName + '/')) tables.push({ name: f.split('/').pop().slice(0, -5), file: unwork(t.file), entries: t.entries });
			} catch {}
		}
		log(`studio: built in the browser: ${b.ok ? 'ok' : 'failed'}, ${b.ms} ms, the module ${b.wasm?.byteLength ?? 'not'} bytes, ${tables.length} table(s)`);
		if (b.ok && b.wasm && !preview.worker) {
			// (a project's first build here: the browser modules its preview imports, as the CLI's page finds them)
			previewBytes = b.wasm;
			meta ??= { root: '/work/' + projectName, imports: await importsOf(b.wasm) };
			startPreview(host);
		} else if (b.ok && b.wasm) {
			previewBytes = b.wasm;
			const snapshot = await new Promise((resolve) => {
				if (!preview.worker) return resolve(null);
				preview.snapshot = resolve;
				preview.worker.postMessage({ type: 'snapshot' });
				setTimeout(() => resolve(null), 3000);
			});
			preview.worker.postMessage({ type: 'start', wasm: await WebAssembly.compile(previewBytes), imports: (meta.imports ?? []).map((p) => new URL(`helder/${p}/imports.mjs`, location.href).href),
				fonts: await previewFonts, gfx, snapshot });
			preview.lastBuild = { req, at: performance.now(), cold };
		}
		answer({ ok: b.ok, diagnostics: (b.diagnostics ?? []).map((d) => ({ ...d, file: unwork(d.file) })), messages: b.messages, ms: b.ms, tables });
	})().catch((e) => answer({ ok: false, why: String(e?.message ?? e) }));
	return id;
}

// ---- the studio's tools (WebTools: the module calls them), WebMCP, a draft's link

let hostRef = null;
const tools = { list: null, queue: [], calls: new Map(), ids: 0 };
let listed;
const toolsListed = new Promise((r) => (listed = r));
const snaps = new Map();
let snapIds = 0;

// a tool's result ({content, isError}), its pending images' PNGs made
function call(name, args = {}) {
	return new Promise((resolve) => {
		const id = ++tools.ids;
		tools.calls.set(id, resolve);
		tools.queue.push(JSON.stringify({ id, name, arguments: args ?? {} }));
		hostRef?.wake?.(0);
	});
}
state.call = call;

async function done(id, json) {
	const r = JSON.parse(json);
	for (const c of r.content ?? [])
		if (c.pending !== undefined) {
			try {
				c.data = await base64(await snaps.get(c.pending));
			} catch (e) {
				Object.assign(c, { type: 'text', text: 'no PNG: ' + e.message });
				delete c.data;
				delete c.mimeType;
			}
			snaps.delete(c.pending);
			delete c.pending;
		}
	tools.calls.get(id)?.(r);
	tools.calls.delete(id);
}

async function base64(blob) {
	const b = new Uint8Array(await blob.arrayBuffer());
	let s = '';
	for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
	return btoa(s);
}

// (drawn at once: the bitmap or the texture's copy is gone after the call)
function png(draw, width, height) {
	const c = new OffscreenCanvas(width, height);
	draw(c.getContext('2d'));
	return c.convertToBlob({ type: 'image/png' });
}
function snap(make) {
	const id = ++snapIds;
	let p;
	try {
		p = make();
	} catch (e) {
		p = Promise.reject(e);
	}
	p.catch(() => {});
	snaps.set(id, p);
	return id;
}

// (a PNG made smaller: a draft's reports)
async function small(data, side = 400) {
	const b = await createImageBitmap(new Blob([Uint8Array.from(atob(data), (c) => c.charCodeAt(0))]));
	const k = Math.min(1, side / Math.max(b.width, b.height)), w = Math.max(1, Math.round(b.width * k)), h = Math.max(1, Math.round(b.height * k));
	const out = await base64(await png((g) => g.drawImage(b, 0, 0, w, h), w, h));
	b.close();
	return out;
}

const text = (v) => ({ content: [{ type: 'text', text: typeof v === 'string' ? v : JSON.stringify(v, null, 2) }], isError: false });
const failed = (e) => ({ content: [{ type: 'text', text: e.message ?? String(e) }], isError: true });
const later = (f) => setTimeout(f, 100);

// the page's own tools: projects in this browser
const pageTools = [
	{
		name: 'project.list',
		description: "The projects in this browser's storage (OPFS) and the examples bundled with the studio; the one open.",
		inputSchema: { type: 'object', properties: {} },
		execute: async () => text({ open: projectName, projects: await projectNames(), examples: examples.map((e) => e.name) }),
	},
	{
		name: 'project.create',
		description: 'Make a new project in this browser and open it (the page loads it: call the tools again once it has). Without files, one design file (app.helder). Paths relative, text files.',
		inputSchema: { type: 'object', properties: { name: { type: 'string' }, files: { type: 'object', additionalProperties: { type: 'string' }, description: '{path: text}' } } },
		execute: async ({ name, files } = {}) => {
			const n = await makeProject(name ?? 'project', files ?? (await newFiles()));
			later(() => go(n));
			return text({ name: n, opening: true });
		},
	},
	{
		name: 'project.open',
		description: 'Open a project of this browser (project.list), or an example by name (a copy made the first time). The page loads it: call the tools again once it has.',
		inputSchema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] },
		execute: async ({ name } = {}) => {
			if ((await projectNames()).includes(name)) later(() => go(name));
			else if (examples.some((e) => e.name === name)) later(() => openExample(name));
			else throw new Error('no project ' + name);
			return text({ name, opening: true });
		},
	},
];

toolsListed.then((list) => {
	const table = [...list.map((t) => ({ ...t, execute: (args) => call(t.name, args) })), ...pageTools.map((t) => ({ ...t, execute: (args) => t.execute(args).catch(failed) }))];
	state.tools = table;
	const mc = document.modelContext ?? navigator.modelContext;
	if (!mc?.registerTool) return;
	for (const t of table)
		try {
			Promise.resolve(mc.registerTool(t)).catch((e) => log('studio: WebMCP: ' + t.name + ': ' + e.message));
		} catch (e) {
			log('studio: WebMCP: ' + t.name + ': ' + e.message);
		}
	state.webmcp = table.length;
});

// A draft's link: the relay's socket; its patches applied as the studio's
// (project.patch: the history, undoable, shown at once), the files the
// studio writes sent back, a report after each change: the check, each
// screen's tree and a small PNG (at most 12 screens)
const link = { ws: null, dirty: new Set(), flush: 0, report: 0, reporting: false, again: false, wait: 1000 };

function connect() {
	const ws = new WebSocket(relay.replace(/^http/, 'ws') + encodeURIComponent(draft.id) + '/live');
	link.ws = ws;
	ws.onopen = () => {
		link.wait = 1000;
		state.linked = true;
		send();
		reportSoon(0);
	};
	ws.onclose = () => {
		state.linked = false;
		link.ws = null;
		setTimeout(connect, (link.wait = Math.min(link.wait * 2, 30000)));
	};
	ws.onmessage = (e) => received(JSON.parse(e.data)).catch((x) => log('studio: the draft: ' + x.message));
}

async function received(m) {
	if (m.type !== 'patch') return;
	const f = dir + '/' + m.path;
	// (a file the studio has not read: written, the page loaded again with it)
	if (!files.has(f)) {
		saveFile(f, m.text);
		await state.saved();
		send();
		link.ws?.send(JSON.stringify({ type: 'applied', seq: m.seq, result: { result: 'reloading' } }));
		return later(() => location.reload());
	}
	let r = await call('project.patch', m.edits ? { path: m.path, edits: m.edits } : { path: m.path, text: m.text });
	// (the edits not applying here, the user's own edits between: the relay's text)
	if (r.isError && m.edits) r = await call('project.patch', { path: m.path, text: m.text });
	const answer = r.content?.[0]?.text ?? '';
	link.ws?.send(JSON.stringify({ type: 'applied', seq: m.seq, result: r.isError ? { error: answer } : JSON.parse(answer) }));
	reportSoon();
}

function changed(path) {
	if (!draft) return;
	link.dirty.add(path.slice(dir.length + 1));
	clearTimeout(link.flush);
	link.flush = setTimeout(send, 300);
	reportSoon();
}

function send() {
	if (!link.ws || link.ws.readyState !== 1 || !link.dirty.size) return;
	link.ws.send(JSON.stringify({ type: 'files', files: Object.fromEntries([...link.dirty].map((p) => [p, files.get(dir + '/' + p)])) }));
	link.dirty.clear();
}

function reportSoon(ms = 800) {
	clearTimeout(link.report);
	link.report = setTimeout(report, ms);
}

async function report() {
	if (!link.ws || link.ws.readyState !== 1) return;
	if (link.reporting) return void (link.again = true);
	link.reporting = true;
	try {
		await toolsListed;
		const info = JSON.parse((await call('project.read')).content[0].text);
		const screens = info.flows.flatMap((f) => f.screens.map((s) => s.name)).slice(0, 12);
		const out = { type: 'results', diagnostics: [], screens: [] };
		const check = await call('build.check');
		if (!check.isError) out.diagnostics.push(...JSON.parse(check.content[0].text).diagnostics);
		for (const name of screens) {
			const s = { name };
			const t = await call('run.tree', { screen: name });
			if (t.isError) s.error = t.content[0].text;
			else {
				s.tree = JSON.parse(t.content[0].text);
				for (const e of s.tree.errors ?? []) out.diagnostics.push({ ...e, screen: name });
			}
			const p = await call('run.snap', { screen: name });
			const img = p.content.find((c) => c.type === 'image');
			if (img) s.png = await small(img.data);
			else s.snapError = p.content[0]?.text;
			out.screens.push(s);
		}
		link.ws?.send(JSON.stringify(out));
		state.reports = (state.reports ?? 0) + 1;
	} catch (e) {
		log('studio: the draft\'s report: ' + e.message);
	} finally {
		link.reporting = false;
		if (link.again) {
			link.again = false;
			reportSoon(0);
		}
	}
}

// ---- the module's imports (studio_web)

function studioWeb(host) {
	hostRef = host;
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
			new_project: () => void newProject(),
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
			tools: (p) => listed(JSON.parse(str(p))),
			tool_next: () => (tools.queue.length ? text(tools.queue.shift()) : 0),
			tool_done: (id, p) => void done(id, str(p)),
			snap_texture: (h) => snap(() => host.gfx.readTexture(h).then((px) => png((g) => g.putImageData(new ImageData(new Uint8ClampedArray(px.data.buffer), px.width, px.height), 0, 0), px.width, px.height))),
			snap_image(h) {
				const b = host.handles.get(h)?.bitmap;
				return snap(() => {
					if (!b) throw new Error('no frame');
					const c = new OffscreenCanvas(b.width, b.height);
					c.getContext('2d').drawImage(b, 0, 0);
					return c.convertToBlob({ type: 'image/png' });
				});
			},
			event(p) {
				const e = JSON.parse(str(p));
				e.ms_page = Math.round(performance.now() - t0);
				state.events.push(e);
				if (e.event === 'first-frame') window.studioLoad?.shown();
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
		onExit: (code, stack) => {
			log('studio: exit ' + code + ' ' + (stack ?? ''));
			if (code) window.studioLoad?.fail('it exited (' + code + ')');
		},
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
	if (draft) {
		state.draft = draft.id;
		connect();
	}
} catch (e) {
	state.error = String(e?.stack ?? e);
	log('studio: ' + state.error);
	window.studioLoad?.fail(e?.message ?? String(e));
}
