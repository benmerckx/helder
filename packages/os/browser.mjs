// Runs a WebAssembly module hxmc built for wasm32-wasi in a browser, with the
// imports of the packages it uses: the browser's counterpart of node's
// hxmc/bootstrap/wasi.mjs.
//
//   import { run } from './browser.mjs';
//   const { host, exitCode } = await run('triangle.wasm', {
//     imports: ['os/imports.mjs', 'gfx/imports.mjs'], canvas: 'demo' });
//
// The import convention: a package whose externs are imports of a module
// (`@:hxmc.lib("hxmc_gfx")`) ships `imports.mjs`, whose default export is a
// function (host) => ({module: {name: function}}), or a promise of that (it
// may wait for what it needs before the module starts: WebGPU's device). The
// objects are merged and the module instantiated, then _start runs main.
// The host each package gets:
//   options        run's options (canvas: an element or its id, for os)
//   memory()       the module's memory; bytes(p, n), string(p) read it (a
//                  view made anew each time: the memory may have grown)
//   handles        the JavaScript objects the module refers to by integer
//                  (add(o) gives the handle, get(h), remove(h); 0 is none)
//   call(f, ...a)  a @:hxmc.callback through its address (an index in the
//                  module's function table), also after main returned; if
//                  the program exits there (proc_exit), its result is
//                  undefined and host.exitCode is set
// WASI preview 1 is what the runtime needs without a file system: the
// arguments and environment, stdout and stderr (lines to options.stdout and
// options.stderr, else the console), the clocks, random bytes, proc_exit;
// any other function fails with ENOSYS.

class Exit {
	constructor(code) {
		this.code = code;
	}
}

export async function run(wasm, options = {}) {
	const args = ['main.wasm', ...(options.args ?? [])];
	const env = Object.entries(options.env ?? {}).map(([k, v]) => `${k}=${v}`);
	let memory = null, exports = null;
	const enc = new TextEncoder();
	const view = () => new DataView(memory.buffer);
	const bytes = (p, n) => new Uint8Array(memory.buffer, p, n);
	const string = (p) => {
		const m = new Uint8Array(memory.buffer);
		let e = p;
		while (m[e]) e++;
		return new TextDecoder().decode(m.subarray(p, e));
	};
	const objects = [null];
	const free = [];
	const handles = {
		add(o) {
			const h = free.length ? free.pop() : objects.length;
			objects[h] = o;
			return h;
		},
		get: (h) => objects[h],
		remove(h) {
			objects[h] = null;
			free.push(h);
		},
	};
	const host = {
		options, handles, bytes, string, exitCode: null,
		memory: () => memory,
		call(f, ...a) {
			if (host.exitCode !== null) return undefined;
			try {
				return exports.__indirect_function_table.get(f)(...a);
			} catch (e) {
				if (!(e instanceof Exit)) throw e;
				host.exitCode = e.code;
				return undefined;
			}
		},
	};

	// stdout and stderr, by lines
	const sinks = {
		1: { out: options.stdout ?? ((s) => console.log(s)), text: '', dec: new TextDecoder() },
		2: { out: options.stderr ?? ((s) => console.error(s)), text: '', dec: new TextDecoder() },
	};
	function write(fd, data) {
		const s = sinks[fd];
		s.text += s.dec.decode(data, { stream: true });
		const lines = s.text.split('\n');
		s.text = lines.pop();
		for (const l of lines) s.out(l);
	}
	// (arguments and environment variables: a table of pointers, then the strings)
	function strings(list, ptrs, buf) {
		const v = view();
		for (const s of list) {
			const b = enc.encode(s + '\0');
			v.setUint32(ptrs, buf, true);
			bytes(buf, b.length).set(b);
			ptrs += 4;
			buf += b.length;
		}
		return 0;
	}
	function sizes(list, count, size) {
		view().setUint32(count, list.length, true);
		view().setUint32(size, list.reduce((n, s) => n + enc.encode(s).length + 1, 0), true);
		return 0;
	}
	const wasi = {
		args_get: (p, b) => strings(args, p, b),
		args_sizes_get: (c, s) => sizes(args, c, s),
		environ_get: (p, b) => strings(env, p, b),
		environ_sizes_get: (c, s) => sizes(env, c, s),
		clock_time_get(id, precision, out) {
			const ns = id === 0 ? BigInt(Date.now()) * 1000000n : BigInt(Math.round(performance.now() * 1e6));
			view().setBigUint64(out, ns, true);
			return 0;
		},
		clock_res_get(id, out) {
			view().setBigUint64(out, 1000n, true);
			return 0;
		},
		fd_write(fd, iovs, n, written) {
			if (!sinks[fd]) return 8; // EBADF
			const v = view();
			let total = 0;
			for (let i = 0; i < n; i++) {
				const p = v.getUint32(iovs + 8 * i, true), len = v.getUint32(iovs + 8 * i + 4, true);
				write(fd, bytes(p, len).slice());
				total += len;
			}
			view().setUint32(written, total, true);
			return 0;
		},
		random_get(p, n) {
			for (let i = 0; i < n; i += 65536) crypto.getRandomValues(bytes(p + i, Math.min(65536, n - i)));
			return 0;
		},
		sched_yield: () => 0,
		fd_prestat_get: () => 8, // EBADF: no preopened directories
		proc_exit(code) {
			throw new Exit(code);
		},
	};
	const imports = { wasi_snapshot_preview1: new Proxy(wasi, { get: (o, k) => o[k] ?? (() => 52) }) }; // ENOSYS
	for (const m of options.imports ?? []) {
		const f = typeof m === 'string' ? (await import(new URL(m, document.baseURI).href)).default : m;
		Object.assign(imports, await f(host));
	}
	// (wasm: a URL, a Response, a compiled WebAssembly.Module or the bytes)
	const instance = wasm instanceof WebAssembly.Module ? await WebAssembly.instantiate(wasm, imports)
		: typeof wasm === 'string' || wasm instanceof Response ? (await WebAssembly.instantiateStreaming(typeof wasm === 'string' ? fetch(wasm) : wasm, imports)).instance
		: (await WebAssembly.instantiate(wasm, imports)).instance;
	exports = instance.exports;
	memory = exports.memory;
	try {
		exports._start();
	} catch (e) {
		if (!(e instanceof Exit)) throw e;
		host.exitCode = e.code;
	}
	return { host, instance, exitCode: host.exitCode ?? 0 };
}
