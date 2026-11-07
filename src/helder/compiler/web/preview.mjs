// helder.compiler.web's preview (README.md): a build's module (the worker's
// build result: wasm, assets) run in this page with the browser modules of
// the packages it imports and helder dev's imports (hxmc_dev), so the
// devtools protocol reaches it without a dev server: the worker's edit
// patches its live literals (Hot.literals) with no build, and a new build
// is swapped in with the running one's state (Hot's snapshot), as helder
// dev's page swaps one (src/helder/cli/page.html).
//
//   import { Preview } from './preview.mjs';
//   const preview = new Preview({ base: '/helder/src/helder/', canvas, fonts });
//   await preview.run(build);                    // build: {wasm, assets?}
//   client.running = (request) => preview.devtools(request);
//   await preview.swap(rebuilt);                 // the state kept
//
// base is where helder's packages are served (base + 'os/browser.mjs',
// base + '<package>/imports.mjs'); fonts the bytes the page gives helder.text
// (it has no system fonts in a browser); canvas the element the program's
// first window draws on (else one is made). It runs in a page: helder.os's
// browser imports draw on the DOM's canvases and read its events.

// the packages with browser modules (src/helder/<package>/imports.mjs)
export const PACKAGES = ['async', 'canvas', 'gfx', 'jobs', 'os', 'text', 'ui', 'web'];

const decoder = new TextDecoder(), encoder = new TextEncoder();

export class Preview {
	constructor({ base, canvas = null, fonts = [], stdout = (s) => console.log(s), stderr = (s) => console.error(s), gfx, env = {} } = {}) {
		this.base = new URL(base, typeof document !== 'undefined' ? document.baseURI : self.location.href);
		this.canvas = canvas;
		this.fonts = fonts;
		this.stdout = stdout;
		this.stderr = stderr;
		this.gfx = gfx;
		this.env = env;
		this.current = null;
		this.gpu = null;
		this.canvases = [];
		this.sources = new Map();
		this.frames = 0;
		this.swaps = 0;
	}

	// the packages a module imports: those whose imports.mjs names one of its import modules (helder.cli.Page's rule)
	async packages(module) {
		const names = [...new Set(WebAssembly.Module.imports(module).map((i) => i.module))].filter((n) => n !== 'wasi_snapshot_preview1' && n !== 'hxmc_dev');
		const out = [];
		for (const p of PACKAGES) {
			let text = this.sources.get(p);
			if (text === undefined) {
				const r = await fetch(new URL(p + '/imports.mjs', this.base));
				text = r.ok ? await r.text() : '';
				this.sources.set(p, text);
			}
			if (names.some((n) => new RegExp('\\b' + n + '\\b').test(text))) out.push(p);
		}
		return out;
	}

	// a build run (its state from snapshot: Hot's, the last one's)
	async run({ wasm, assets = null }, snapshot = null) {
		const module = wasm instanceof WebAssembly.Module ? wasm : await WebAssembly.compile(wasm);
		const imports = (await this.packages(module)).map((p) => new URL(p + '/imports.mjs', this.base).href);
		const state = { host: null, reloadFn: 0, devtoolsFn: 0, snapshot: null, inbox: null, waiting: new Map(), exited: null };
		const self = this;
		const restore = snapshot === null ? null : encoder.encode(snapshot);
		const dev = (h) => {
			state.host = h;
			return {
				hxmc_dev: {
					restore_length: () => (restore === null ? -1 : restore.length),
					restore_take: (p) => h.bytes(p, restore.length).set(restore),
					register: (f) => (state.reloadFn = f),
					send: (p, n) => (state.snapshot = decoder.decode(h.bytes(p, n).slice())),
					frame: () => self.frames++,
					devtools: (f) => (state.devtoolsFn = f),
					devtools_take: (p) => h.bytes(p, state.inbox.length).set(state.inbox),
					devtools_send: (p, n) => self.received(state, decoder.decode(h.bytes(p, n).slice())),
					asset_register: () => {},
					asset_length: () => -1,
					asset_take: () => {},
				},
			};
		};
		// (the files the build read before main: served from blobs)
		const files = {};
		for (const [p, b] of Object.entries(assets ?? {})) files[p] = URL.createObjectURL(new Blob([b]));
		const { run } = await import(new URL('os/browser.mjs', this.base).href);
		this.current = state;
		await run(module, {
			imports: [...imports, dev], fonts: this.fonts, stdout: this.stdout, stderr: this.stderr, track: true,
			canvas: this.canvases[0] ?? this.canvas ?? undefined, gpu: this.gpu ?? undefined, gfx: this.gfx, files, env: this.env,
			onExit: (code) => (state.exited = code),
		});
		const g = state.host.gfx;
		if (!this.gpu && g?.device) this.gpu = { adapter: g.adapter, device: g.device };
		return state;
	}

	// a new build in place of the running one, its state kept (helder dev's swap)
	async swap(build) {
		const old = this.current;
		let snapshot = null;
		if (old?.host) {
			old.host.swapping = true;
			if (old.reloadFn) old.host.call(old.reloadFn);
			snapshot = old.snapshot;
			for (const w of old.waiting.values()) w(null);
			old.host.dispose();
			if (old.host.os?.canvases?.length) this.canvases = old.host.os.canvases;
		}
		this.current = null;
		const s = await this.run(build, snapshot);
		this.swaps++;
		return s;
	}

	// a devtools request (helder's devtools protocol: {method, params}) to the
	// running program, its JSON-RPC response; null when none runs or it does not answer in ms
	devtools(request, ms = 2000) {
		const s = this.current;
		if (!s?.devtoolsFn || s.exited !== null) return Promise.resolve(null);
		const id = 'p' + (Preview.next = (Preview.next ?? 0) + 1);
		return new Promise((resolve) => {
			const timer = setTimeout(() => {
				s.waiting.delete(id);
				resolve(null);
			}, ms);
			s.waiting.set(id, (r) => {
				clearTimeout(timer);
				resolve(r);
			});
			s.inbox = encoder.encode(JSON.stringify({ jsonrpc: '2.0', id, method: request.method, params: request.params ?? {} }));
			s.host.call(s.devtoolsFn, s.inbox.length);
		});
	}

	// a message from the program: a response to one of ours (the rest, its own requests and notifications, to onMessage)
	received(state, text) {
		let m = null;
		try {
			m = JSON.parse(text);
		} catch {
			return;
		}
		const w = m.id !== undefined && m.method === undefined ? state.waiting.get(m.id) : undefined;
		if (w) {
			state.waiting.delete(m.id);
			w(m);
		} else this.onMessage?.(m);
	}

	dispose() {
		const s = this.current;
		this.current = null;
		if (!s?.host) return;
		for (const w of s.waiting.values()) w(null);
		s.host.dispose();
	}
}
