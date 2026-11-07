// helder.compiler.web's toolchain (README.md), what the worker (worker.mjs)
// runs: helder's compiler as wasm32-wasi (helder.compiler.web.WebMain)
// resident in this thread, TypeScript's API as a wasip1 reactor beside it,
// one file system (vfs.mjs) for both. No DOM, no worker globals: node runs
// it too (tests).
//
//   const t = await Toolchain.start({ compiler, typescript, bundle, transport });
//   t.write('/work/app/main.tsx', text);
//   const b = await t.build({ entry: '/work/app' });
//
// compiler, typescript: a WebAssembly.Module, its bytes, a Response or a
// promise of one; bundle: the sources' bytes (build.mjs's sources.bundle);
// transport: typescript/wasm's module ({WasmTransport, instantiateWasm}).
import { Exit, Vfs, Wasi } from './vfs.mjs';

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const HELDER = '/node_modules/helder';
const LIBS = '/node_modules/@typescript/typescript-wasip1-wasm/lib';

async function compile(m) {
	m = await m;
	if (m instanceof WebAssembly.Module) return m;
	if (typeof Response !== 'undefined' && m instanceof Response) return WebAssembly.compileStreaming ? WebAssembly.compileStreaming(m) : WebAssembly.compile(await m.arrayBuffer());
	return WebAssembly.compile(m);
}

export class Toolchain {
	constructor() {
		this.vfs = new Vfs();
		this.log = (text) => console.log(text);
		// the running preview: (request) => response | null (a promise of one)
		this.running = null;
		this.builds = 0;
		this.tsMs = 0;
		this.changed = new Set();
		this.lastBuild = null;
	}

	static async start(options) {
		const t = new Toolchain();
		await t.init(options);
		return t;
	}

	async init({ compiler, typescript = null, bundle, transport = null, persist = true, log, env = {} }) {
		if (log) this.log = log;
		const ms = {};
		let t0 = performance.now();
		const [cm, tm, bytes] = await Promise.all([compile(compiler), typescript ? compile(typescript) : null, bundle]);
		ms.compile = performance.now() - t0;
		t0 = performance.now();
		this.files = this.vfs.unbundle(bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes), '/node_modules');
		for (const d of ['/work', '/out', '/cache']) this.vfs.mkdirs(d);
		this.persistent = persist ? await this.vfs.restore('/cache') : false;
		ms.unpack = performance.now() - t0;
		t0 = performance.now();
		if (tm) await this.startTypescript(tm, transport);
		ms.typescript = performance.now() - t0;
		t0 = performance.now();
		this.startCompiler(cm, env);
		ms.instantiate = performance.now() - t0;
		t0 = performance.now();
		const v = this.request({ kind: 'compile', words: ['--version'], cwd: '/' });
		this.version = v.printed || v.messages;
		ms.warm = performance.now() - t0;
		this.ms = ms;
		return ms;
	}

	async startTypescript(module, transport) {
		const err = (text) => this.log('typescript: ' + text);
		const instance = await transport.instantiateWasm(module, { stdout: err, stderr: err });
		this.tsInstance = instance;
		this.tsgo = new transport.WasmTransport({ instance, cwd: '/', useCaseSensitiveFileNames: true, fs: this.vfs.typescript(LIBS) });
	}

	startCompiler(module, env) {
		const out = { 1: [], 2: [] };
		const wasi = new Wasi(this.vfs, {
			args: ['helder-compiler'],
			env: {
				PWD: '/', HOME: '/cache', HXMC_CACHE: '/cache/hxmc', HELDER_CACHE: '/cache/helder', HELDER_SRC: HELDER + '/src', HELDER_TYPESCRIPT: '/node_modules/typescript',
				// (a resident compiler keeps what it makes: a large nursery and old space spare it collections)
				RT_MINOR_KB: '32768', RT_STACK_MB: '16', ...env,
			},
			out: (fd, b) => {
				// (lines; the compiler's own output, not a request's, which its answer carries)
				const buf = out[fd];
				for (const c of b) {
					if (c === 10) {
						this.log(decoder.decode(new Uint8Array(buf)));
						buf.length = 0;
					} else buf.push(c);
				}
			},
		});
		this.wasi = wasi;
		const self = this;
		let tsLast = new Uint8Array(0);
		const mem = () => new Uint8Array(wasi.memory.buffer);
		const imports = wasi.imports();
		imports.helder_compiler = {
			register: (f) => (self.requestFn = f),
			take: (p) => mem().set(self.pending, p),
			reply: (p, n) => (self.answer = decoder.decode(mem().slice(p, p + n))),
		};
		imports.helder_tsgo = {
			open: () => (self.tsgo ? 0 : 1),
			request: (mp, mn, pp, pn) => {
				const method = decoder.decode(mem().slice(mp, mp + mn));
				const payload = mem().slice(pp, pp + pn);
				const t0 = performance.now();
				try {
					tsLast = self.tsgo.requestBinarySync(method, payload);
					self.tsMs += performance.now() - t0;
					return tsLast.length;
				} catch (e) {
					tsLast = encoder.encode(String(e?.message ?? e));
					return -tsLast.length - 1;
				}
			},
			take: (p) => mem().set(tsLast, p),
		};
		// (what the compiler links but never calls here: helder.async's loop)
		for (const i of WebAssembly.Module.imports(module))
			if (i.kind === 'function' && !imports[i.module]?.[i.name]) (imports[i.module] ??= {})[i.name] = () => {
				throw new Error(`helder's compiler called ${i.module}.${i.name}, which the worker does not have`);
			};
		const instance = new WebAssembly.Instance(module, imports);
		wasi.memory = instance.exports.memory;
		this.instance = instance;
		try {
			instance.exports._start();
		} catch (e) {
			if (!(e instanceof Exit)) throw e;
			throw new Error(`helder's compiler exited with ${e.code} as it started`);
		}
		if (!this.requestFn) throw new Error("helder's compiler did not register its requests");
		this.call = instance.exports.__indirect_function_table.get(this.requestFn);
	}

	// a request to the compiler (WebMain's), its answer
	request(m) {
		this.pending = encoder.encode(JSON.stringify(m));
		this.answer = null;
		try {
			this.call(this.pending.length);
		} catch (e) {
			if (e instanceof Exit) throw new Error(`helder's compiler exited with ${e.code}`);
			throw e;
		}
		const a = JSON.parse(this.answer ?? '{"error": "no answer"}');
		if (a.error) throw new Error(a.error);
		return a;
	}

	write(path, content) {
		if (content === null) this.vfs.remove(path);
		else this.vfs.writeFile(path, content);
		this.changed.add(path);
	}

	// the files changed since the last request told to the compilation server
	invalidate(files = []) {
		for (const f of files) this.changed.add(f);
		for (const f of this.changed)
			if (f.endsWith('.hx') && this.vfs.lookup(f))
				this.request({ kind: 'compile', cwd: '/', words: ['--display', JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'server/invalidate', params: { file: f } })] });
		this.changed.clear();
	}

	// a compilation (check's, build's). Once another program was built in the
	// server and one of them failed, helder.view's ViewRuntime may be cached
	// without the fields its build macro keeps (HostMacro: "the runtime's
	// fields are not known"): it is invalidated and the request made again
	compile(cwd, words) {
		const r = this.request({ kind: 'compile', cwd, words });
		if (r.ok || !r.messages.includes("the runtime's fields are not known")) return r;
		this.invalidate([HELDER + '/src/helder/view/ViewRuntime.hx']);
		return this.request({ kind: 'compile', cwd, words });
	}

	// an entry's compiler words (helder.cli.Entry's, for the web)
	entry(entry) {
		const dir = this.vfs.lookup(entry)?.dir ? entry : entry.replace(/\/[^/]*$/, '') || '/';
		return { ...this.request({ kind: 'entry', entry, target: 'web', cwd: dir }), cwd: dir };
	}

	check({ entry, changed = [], args = [] }) {
		const t0 = performance.now();
		this.invalidate(changed);
		const e = this.entry(entry);
		// (hxmc's target named, as a build's, so the frontends run: tsgo's check is TypeScript's part; --no-output writes nothing
		// of a Haxe program's, a TypeScript one's lowering writes its module, removed)
		const out = `/out/.check/${e.name}.wasm`;
		const r = this.compile(e.cwd, [...e.words, ...args, '--custom-target', 'hxmc=' + out, '--no-output']);
		for (const p of this.vfs.list('/out/.check')) this.vfs.remove(p);
		return { ok: r.ok, diagnostics: r.diagnostics, ms: Math.round(performance.now() - t0) };
	}

	build({ entry, dev = true, out = null, changed = [], args = [] }) {
		const t0 = performance.now();
		this.tsMs = 0;
		this.invalidate(changed);
		const e = this.entry(entry);
		out ??= `/out/${e.name}.wasm`;
		const literals = `/out/.literals/${e.name}`;
		const words = [...e.words, ...(dev ? ['-D', 'hxmc.dev', '-D', 'disable-hxb-cache', '-D', 'helder.literals=' + literals] : ['-dce', 'full', '-D', 'helder.release']), ...args, '--custom-target', 'hxmc=' + out];
		this.vfs.remove(out);
		const r = this.compile(e.cwd, words);
		const wasm = r.ok ? this.vfs.readFile(out) : null;
		if (r.ok && dev) this.request({ kind: 'sources', dir: literals });
		this.builds++;
		this.lastBuild = { entry, out, dev };
		const result = { ok: r.ok && wasm !== null, diagnostics: r.diagnostics, messages: r.messages, printed: r.printed, ms: Math.round(performance.now() - t0), tsgoMs: Math.round(this.tsMs), out };
		if (wasm) {
			result.wasm = wasm.slice();
			const assets = this.vfs.readText(out + '.assets.json');
			if (assets) {
				result.assets = {};
				for (const p of JSON.parse(assets)) {
					const b = this.vfs.readFile(p.startsWith('/') ? p : out.replace(/\/[^/]*$/, '') + '/' + p);
					if (b) result.assets[p] = b.slice();
				}
			}
		}
		return result;
	}

	// saved files against the last dev build: live literals patched in the
	// running preview (Hot.literals), nothing built; else a build's (why)
	async edit({ files = {}, changed = [] }) {
		const t0 = performance.now();
		const done = (r) => ({ ...r, ms: Math.round((performance.now() - t0) * 10) / 10 });
		for (const [p, text] of Object.entries(files)) this.write(p, text);
		const paths = [...Object.keys(files), ...changed];
		if (!this.lastBuild?.dev) return done({ kind: 'build', why: 'no dev build yet' });
		let all = [];
		for (const f of paths) {
			const r = this.request({ kind: 'patches', file: f });
			if (!r.patches) return done({ kind: 'build', why: f.replace(/.*\//, '') + ': ' + r.why });
			all = all.concat(r.patches);
		}
		if (all.length === 0) return done({ kind: 'unchanged' });
		const answer = await this.ask({ method: 'Hot.literals', params: { set: all } }, 2000);
		const r = answer?.result;
		if (!r) return done({ kind: 'build', why: answer ? `the program did not take the literals (${answer.error?.message ?? 'no answer'})` : 'no program connected to patch' });
		const stale = r.stale ?? [];
		if (stale.length) return done({ kind: 'build', why: `${stale.length} read once, not bound: ${stale.join(', ')}` });
		this.request({ kind: 'took', list: all });
		return done({ kind: 'patched', literals: all });
	}

	async reload(params) {
		const answer = await this.ask({ method: 'Runtime.reload', params }, 10000);
		return !!answer && !answer.error;
	}

	// a devtools request to the running preview (null: none, or no answer in time)
	async ask(request, ms) {
		if (!this.running) return null;
		return Promise.race([Promise.resolve(this.running(request)).catch(() => null), new Promise((r) => setTimeout(() => r(null), ms))]);
	}

	stats() {
		const s = this.vfs.stats();
		return { memory: { compiler: this.wasi.memory.buffer.byteLength, typescript: this.tsInstance?.exports.memory.buffer.byteLength ?? 0 }, files: s.files, bytes: s.bytes, builds: this.builds };
	}
}
