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
//   options        run's options (canvas: an element or its id, and
//                  audioContext: a function (sampleRate, channels) =>
//                  an AudioContext or OfflineAudioContext, and
//                  touchAction: the canvas's CSS touch-action, by default
//                  'none' (every touch drag the program's; 'pan-y': the
//                  page scrolls on vertical swipes over the canvas), for os; gfx:
//                  'webgl2' for gfx, WebGL2 even where WebGPU is, and
//                  antialias: true, the canvas's frames multisampled)
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
//
// A module built with -D hxmc.wasm-gc (its Haxe values in the engine's
// collector, a small linear memory for what crosses to the host: the same
// memory(), handles and call for the packages) imports the runtime's host
// as "hxmc" instead (hxmc/bootstrap/wasmgc.mjs is node's): the output, the
// clocks, Math, float formatting and parsing, the calendar, exit; no files.
//
// Memory: the module's own memory grows as it needs (the runtime reports
// what memory.grow refused on stderr: "out of memory: ..."); a RangeError of
// the browser's (the memory of a new instance, an ArrayBuffer) becomes
// an Error whose message says "out of memory" and how much was asked.

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
	// (-D hxmc.wasm-gc: its strings are arrays of UTF-16 units, read and made through its exports)
	const str = (s) => {
		if (s === null) return null;
		const n = exports.hxmc_str_len(s);
		let out = '';
		for (let i = 0; i < n; i += 4096) {
			const units = [];
			for (let k = i; k < Math.min(n, i + 4096); k++) units.push(exports.hxmc_str_get(s, k));
			out += String.fromCharCode(...units);
		}
		return out;
	};
	const ofJs = (t) => {
		const s = exports.hxmc_str_new(t.length);
		for (let i = 0; i < t.length; i++) exports.hxmc_str_set(s, i, t.charCodeAt(i));
		return s;
	};
	const math = [Math.sin, Math.cos, Math.tan, Math.asin, Math.acos, Math.atan, Math.atan2, Math.exp, Math.log, Math.pow];
	const gc = {
		write: (fd, s) => write(fd === 2 ? 2 : 1, enc.encode(str(s))),
		now: () => performance.now() / 1000,
		fmt: (v) => ofJs(String(v)),
		parseFloat: (s) => parseFloat(str(s)),
		math: (op, x, y) => math[op](x, y),
		random: Math.random,
		// (GcSys's op codes: the environment, the arguments; no files)
		sysStr(op, a) {
			switch (op) {
				case 0: return options.env?.[str(a)] === undefined ? null : ofJs(options.env[str(a)]);
				case 4: return ofJs(args.slice(1).join('\0'));
				case 5: return ofJs(env.join('\0'));
				case 6: return ofJs(args[0]);
				case 8: return ofJs('Wasi');
				default: return null;
			}
		},
		sysNum(op, a, b, n) {
			switch (op) {
				case 7: throw new Exit(n);
				case 8: return Date.now() / 1000;
				case 9: return performance.now() / 1000;
				default: return 0;
			}
		},
		readFile: () => null,
		writeFile: () => 0,
		dateNum(op, t, y, m, d, h, mi, s) {
			const date = new Date(t);
			const f = [null, 'FullYear', 'Month', 'Date', 'Day', 'Hours', 'Minutes', 'Seconds'];
			if (op === 0) return new Date(y, m, d, h, mi, s).getTime();
			if (op <= 7) return date['get' + f[op]]();
			if (op <= 14) return date['getUTC' + f[op - 7]]();
			return op === 15 ? date.getTimezoneOffset() : Date.now();
		},
	};
	const imports = { wasi_snapshot_preview1: new Proxy(wasi, { get: (o, k) => o[k] ?? (() => 52) }), hxmc: gc }; // ENOSYS
	for (const m of options.imports ?? []) {
		const f = typeof m === 'string' ? (await import(new URL(m, document.baseURI).href)).default : m;
		Object.assign(imports, await f(host));
	}
	// (wasm: a URL, a Response, a compiled WebAssembly.Module or the bytes)
	let instance;
	try {
		instance = wasm instanceof WebAssembly.Module ? await WebAssembly.instantiate(wasm, imports)
			: typeof wasm === 'string' || wasm instanceof Response ? (await WebAssembly.instantiateStreaming(typeof wasm === 'string' ? fetch(wasm) : wasm, imports)).instance
			: (await WebAssembly.instantiate(wasm, imports)).instance;
	} catch (e) {
		throw outOfMemory(e, await initialMemory(wasm).catch(() => 0));
	}
	exports = instance.exports;
	memory = exports.memory;
	try {
		exports._start();
	} catch (e) {
		if (!(e instanceof Exit)) throw outOfMemory(e, 0, memory);
		host.exitCode = e.code;
	}
	return { host, instance, exitCode: host.exitCode ?? 0 };
}

// a RangeError where the browser refused memory, as "out of memory: ..." with
// the size asked (bytes, when known) and the memory in use; e itself otherwise
// (a deep recursion's "Maximum call stack size exceeded" is no memory error)
export function outOfMemory(e, bytes, memory = null) {
	if (!(e instanceof RangeError) || !/memory|alloc/i.test(e.message) || /call stack/i.test(e.message)) return e;
	const mb = (n) => (n / 1048576).toFixed(1) + ' MB';
	const r = new Error('out of memory: ' + (bytes ? 'the browser refused ' + mb(bytes) + ' of WebAssembly memory' : 'the browser refused memory')
		+ (memory ? ' (the module has ' + mb(memory.buffer.byteLength) + ')' : '') + ': ' + e.message, { cause: e });
	r.outOfMemory = true;
	return r;
}

// the initial size of a module's memory (bytes): its memory section's limits
async function initialMemory(wasm) {
	const b = new Uint8Array(wasm instanceof WebAssembly.Module ? [] : typeof wasm === 'string' ? await (await fetch(wasm)).arrayBuffer()
		: wasm instanceof Response ? [] : wasm.buffer ? new Uint8Array(wasm.buffer, wasm.byteOffset, wasm.byteLength) : wasm);
	let p = 8;
	const leb = () => {
		let r = 0, k = 0, x;
		do {
			x = b[p++];
			r += (x & 0x7f) * 2 ** k;
			k += 7;
		} while (x & 0x80);
		return r;
	};
	while (p < b.length) {
		const id = b[p++], size = leb(), end = p + size;
		if (id === 5 && leb() > 0) {
			p++; // (the limits' flags)
			return leb() * 65536;
		}
		p = end;
	}
	return 0;
}
