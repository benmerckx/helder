// The studio's preview host in a Web Worker (helder.story.web.Preview): the
// project's program, a dev build for the web, run here with every story in
// one helder.story.Host, its frames to the page as ImageBitmaps.
//
//   const w = new Worker(new URL('helder/story/web/worker.mjs', base), { type: 'module' });
//   w.postMessage({ type: 'start', wasm: module, imports: [url, ...], fonts: [bytes, ...], gfx });
//   w.postMessage({ type: 'line', line: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'Ui.getTree', params: { screen } }) });
//   w.onmessage = (e) => ...  // {type: 'frame', screen, version, width, height, bitmap}, {type: 'line', line}, {type: 'log', text}, {type: 'exit', code}
//
// The page's messages: start (the module: a WebAssembly.Module, a URL or
// the bytes; imports: the URLs of the imports.mjs of the packages it uses,
// helder.story.web's added; fonts: the fonts helder.text has, as bytes or
// URLs; gfx: 'webgl2' for WebGL2 even where WebGPU is; snapshot: the state
// of the build before, a reload's), line (a protocol line for the program,
// queued until it runs), stop (the program's loop ended, its GPU objects
// released: before a new build's start).
import { run } from '../../os/browser.mjs';

// (what a page has and a worker does not, read by helder.os's imports)
globalThis.devicePixelRatio ??= 1;
const queue = [];
let current = null;
let snapshot = null;

// (the page's messages in order, each after the one before is done: a
// start's program running before the next snapshot or start is handled)
let turn = Promise.resolve();
self.onmessage = (e) => {
	const m = e.data;
	if (m.type === 'line') return queue.push(m.line);
	turn = turn.then(() => handle(m));
};

async function handle(m) {
	if (m.type === 'stop') return stop();
	// (a new build coming: the running one's state, helder.dev.Hot's snapshot, posted as {type: 'snapshot'})
	// (its loop ended there: what it built is disposed)
	if (m.type === 'snapshot') {
		if (!current?.preview?.reload) return postMessage({ type: 'snapshot', snapshot: null });
		current.preview.stop();
		current.call(current.preview.reload);
		return;
	}
	// (the program's memory: its module's linear memory, bytes)
	if (m.type === 'stats') return postMessage({ type: 'stats', memory: current?.memory()?.buffer.byteLength ?? 0 });
	if (m.type !== 'start') return;
	stop();
	snapshot = m.snapshot ?? null;
	try {
		const imports = await Promise.all([...m.imports, new URL('imports.mjs', import.meta.url).href].map(async (u) => (await import(u)).default));
		imports.push(dev);
		const t0 = performance.now();
		const r = await run(m.wasm, {
			imports, fonts: m.fonts ?? [], gfx: m.gfx, antialias: false, env: { HXMC_DEV_PROTOCOL: '1', ...(m.env ?? {}) },
			preview: { queue },
			onFrame: (f) => postMessage({ type: 'frame', ...f }, [f.bitmap]),
			onLine: (line) => postMessage({ type: 'line', line }),
			stdout: (text) => postMessage({ type: 'log', text }),
			stderr: (text) => postMessage({ type: 'log', text, error: true }),
			onExit: (code, stack) => postMessage({ type: 'exit', code, stack }),
			onError: (err) => postMessage({ type: 'log', text: String(err), error: true }),
		});
		current = r.host;
		postMessage({ type: 'started', ms: performance.now() - t0, backend: r.host.gfx?.backend ?? null });
	} catch (err) {
		postMessage({ type: 'exit', code: 1, stack: String(err?.stack ?? err) });
	}
}

function stop() {
	if (!current) return;
	current.preview?.stop();
	try {
		current.gfx?.release?.();
	} catch {}
	current = null;
	queue.length = 0;
}

// (hxmc dev's imports, helder.dev.Hot's on the web: the snapshot of the build before, a reload's)
function dev(host) {
	const enc = new TextEncoder();
	host.preview ??= {};
	return {
		hxmc_dev: {
			restore_length: () => (snapshot === null ? -1 : enc.encode(snapshot).length),
			restore_take(p) {
				const b = enc.encode(snapshot);
				host.bytes(p, b.length + 1).set([...b, 0]);
			},
			register(f) {
				host.preview.reload = f;
			},
			send(p, n) {
				postMessage({ type: 'snapshot', snapshot: new TextDecoder().decode(host.bytes(p, n)) });
			},
			frame() {},
			// (Hot's own devtools channel and helder.asset's reloads: the host speaks over its own, Preview's)
			devtools() {},
			devtools_take() {},
			devtools_send() {},
			asset_register() {},
			asset_length: () => -1,
			asset_take() {},
		},
	};
}
