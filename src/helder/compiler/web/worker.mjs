// helder.compiler.web's worker (README.md, protocol.d.ts): the toolchain
// (toolchain.mjs) answering the page's messages, one at a time, in order.
//   new Worker(new URL('worker.mjs', base), { type: 'module' })
// Its files are fetched from beside it unless init's assets say otherwise:
// build.mjs's helder-compiler.wasm, tsc.wasm, sources.bundle and typescript/
// (typescript/wasm's transport).
import { Toolchain } from './toolchain.mjs';

const PROTOCOL = 1;
let toolchain = null;
let queue = Promise.resolve();
let rid = 1;
const asked = new Map();
const post = (m, transfer = []) => self.postMessage(m, transfer);

// a download with its progress, its bytes as served
async function fetchBytes(url, phase, counted) {
	const r = await fetch(url);
	if (!r.ok) throw new Error(`${url}: ${r.status}`);
	const total = Number(r.headers.get('content-length')) || 0;
	const reader = r.body.getReader(), chunks = [];
	let loaded = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value);
		loaded += value.length;
		post({ type: 'progress', phase, loaded, total });
	}
	// (the bytes as served: the header's, compressed; else what arrived)
	counted.push(total || loaded);
	const out = new Uint8Array(loaded);
	let at = 0;
	for (const c of chunks) {
		out.set(c, at);
		at += c.length;
	}
	return out;
}

async function init(m) {
	const t0 = performance.now();
	const base = new URL('.', m.assets?.base ?? self.location.href);
	const at = (name, given) => new URL(given ?? name, base);
	const urls = { compiler: at('helder-compiler.wasm', m.assets?.compiler), typescript: m.assets?.typescript === null ? null : at('tsc.wasm', m.assets?.typescript), bundle: at('sources.bundle', m.assets?.bundle) };
	const sizes = { compiler: [], typescript: [], bundle: [] };
	const [compiler, typescript, bundle, transport] = await Promise.all([
		fetchBytes(urls.compiler, 'download', sizes.compiler),
		urls.typescript ? fetchBytes(urls.typescript, 'download', sizes.typescript) : null,
		fetchBytes(urls.bundle, 'download', sizes.bundle),
		urls.typescript ? import(new URL('typescript/dist/wasm/index.js', m.assets?.transport ?? base).href) : null,
	]);
	const download = performance.now() - t0;
	post({ type: 'progress', phase: 'compile' });
	toolchain = await Toolchain.start({ compiler, typescript, bundle, transport, persist: m.persist !== false, log: (text) => post({ type: 'log', text }) });
	toolchain.running = (request) => new Promise((resolve) => {
		const id = rid++;
		asked.set(id, resolve);
		post({ type: 'running', rid: id, request });
	});
	const ms = toolchain.ms;
	return {
		protocol: PROTOCOL,
		versions: { hxmc: toolchain.version, typescript: toolchain.tsgo ? 'wasip1' : null },
		threads: false,
		persistent: toolchain.persistent,
		ms: { download: Math.round(download), compile: Math.round(ms.compile), unpack: Math.round(ms.unpack), warm: Math.round(ms.typescript + ms.instantiate + ms.warm), total: Math.round(performance.now() - t0) },
		bytes: { compiler: sizes.compiler[0] ?? 0, typescript: sizes.typescript[0] ?? 0, bundle: sizes.bundle[0] ?? 0 },
	};
}

async function handle(m) {
	if (m.type === 'init') return init(m);
	if (!toolchain) throw new Error('the compiler worker is not started: init first');
	const t = toolchain;
	switch (m.type) {
		case 'write':
			for (const [p, c] of Object.entries(m.files)) t.write(p, c);
			return {};
		case 'read': {
			const b = t.vfs.readFile(m.path);
			if (b === null) throw new Error(m.path + ': no such file');
			return b.slice();
		}
		case 'list':
			return t.vfs.list(m.dir);
		case 'check':
			return t.check(m);
		case 'build': {
			const r = t.build(m);
			// (OPFS: the caches written by the build, after it answered)
			setTimeout(() => t.vfs.persist(), 0);
			return r;
		}
		case 'invalidate':
			t.invalidate(m.files);
			return {};
		case 'edit':
			return t.edit(m);
		case 'reload':
			return t.reload(m.params);
		case 'stats':
			return t.stats();
		default:
			throw new Error('unknown request ' + m.type);
	}
}

self.onmessage = (e) => {
	const m = e.data;
	if (m.type === 'running' && m.id === undefined) {
		// (the page's answer to a running request: not queued, an edit waits for it)
		asked.get(m.rid)?.(m.response);
		asked.delete(m.rid);
		return;
	}
	queue = queue.then(async () => {
		try {
			const result = await handle(m);
			const transfer = [];
			if (result instanceof Uint8Array) transfer.push(result.buffer);
			if (result?.wasm) transfer.push(result.wasm.buffer);
			post({ id: m.id, type: 'result', result }, transfer);
		} catch (err) {
			post({ id: m.id, type: 'error', message: String(err?.stack ?? err?.message ?? err) });
		}
	});
};
