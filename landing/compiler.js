// The compiler's worker: haxe.wasm (@hxmc/wasm) over a MemFS of the std and
// the packages' sources, fetched once; each target's runtime objects fetched
// the first time a download asks for that target. The page (app.js) sends
//   {type: 'init'}
//   {type: 'compile', id, example, target, edits: {path: source}}
// and gets back
//   {type: 'progress', what, loaded, total}   (the downloads)
//   {type: 'ready'}
//   {type: 'files', files: [[path, writing], ...]}   (what the compiler opens, batched)
//   {type: 'done', id, ok, bytes, file, assets, log, ms}
//   {type: 'error', id?, message}
import { compile } from './compile.js';
import { MemFS, unpack } from './wasi.js';

const fs = new MemFS();
let manifest = null;
let module = null;
let ready = null;
const runtimes = new Map();
// (edited files: restored before the next build, so that one edit is not
// carried to another example)
const originals = new Map();

// a file of the site, its download reported as it goes (sizes from the
// manifest: a server's Content-Length is the compressed size)
async function load(path, what) {
	const r = await fetch(new URL(path, self.location.href));
	if (!r.ok) throw new Error(`${path}: ${r.status} ${r.statusText}`);
	const total = manifest.sizes[path] ?? +(r.headers.get('content-length') ?? 0);
	const reader = r.body.getReader();
	const chunks = [];
	let loaded = 0, last = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value);
		loaded += value.length;
		const now = performance.now();
		if (now - last > 60) {
			last = now;
			postMessage({ type: 'progress', what, loaded, total });
		}
	}
	postMessage({ type: 'progress', what, loaded, total: loaded });
	const b = new Uint8Array(loaded);
	let at = 0;
	for (const c of chunks) {
		b.set(c, at);
		at += c.length;
	}
	return b;
}

function init() {
	ready ??= (async () => {
		manifest = await (await fetch(new URL('manifest.json', self.location.href))).json();
		const [wasm, std, src] = await Promise.all([load('haxe.wasm', 'compiler'), load('std.pack', 'std'), load('src.pack', 'sources')]);
		fs.mount('/lib', unpack(std));
		fs.mount('/lib/src', unpack(src));
		module = await WebAssembly.compile(wasm);
	})();
	return ready;
}

function runtime(target) {
	if (target === 'wasm32-wasi') return Promise.resolve();
	if (!runtimes.has(target))
		runtimes.set(target, load(`rt/${target}.pack`, `runtime ${target}`).then((b) => fs.mount('/lib/rt', unpack(b))));
	return runtimes.get(target);
}

async function build({ id, example, target, edits = {} }) {
	await init();
	await runtime(target);
	for (const [p, text] of originals) fs.write(`/lib/src/${p}`, text);
	originals.clear();
	for (const [p, text] of Object.entries(edits)) {
		originals.set(p, fs.read(`/lib/src/${p}`));
		fs.write(`/lib/src/${p}`, new TextEncoder().encode(text));
	}
	let batch = [], last = 0;
	const r = await compile({
		module, fs, example, target,
		onOpen(path, writing) {
			batch.push([path, writing]);
			const now = performance.now();
			if (now - last > 40) {
				last = now;
				postMessage({ type: 'files', files: batch });
				batch = [];
			}
		},
	});
	if (batch.length) postMessage({ type: 'files', files: batch });
	const transfer = [r.bytes, ...r.assets.map(([, b]) => b)].filter(Boolean).map((b) => b.buffer);
	postMessage({ type: 'done', id, ...r }, transfer);
}

self.onmessage = async ({ data }) => {
	try {
		if (data.type === 'init') {
			await init();
			postMessage({ type: 'ready' });
		} else if (data.type === 'compile') await build(data);
	} catch (e) {
		postMessage({ type: 'error', id: data.id, message: String(e?.message ?? e) });
	}
};
