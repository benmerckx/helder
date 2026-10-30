// A worker of helder.jobs (imports.mjs makes it): the program's module
// instantiated again, with a WASI of its own (no files: no arguments, the
// environment ENV's runtime sizes, stdout and stderr to the console, the
// clocks, random bytes) and the other packages' imports answered with 0. Its _start runs
// the static initializers until WebJobs' __init__, which calls serve and
// exits (proc_exit, thrown here); then each job posted runs by its
// callback's index, its input copied into the instance's memory, its
// output out of it (transferred). A Web Worker in a browser,
// worker_threads under node.
const node = typeof process !== 'undefined' && !!process.versions?.node && typeof self === 'undefined';
const port = node ? (await import('node:worker_threads')).parentPort : self;
const listen = (f) => (node ? port.on('message', f) : (port.onmessage = (e) => f(e.data)));

class Exit {
	constructor(code) {
		this.code = code;
	}
}

let exports = null, execute = 0, input = null, output = null;
const memory = () => new Uint8Array(exports.memory.buffer);
const view = () => new DataView(exports.memory.buffer);
const lines = { 1: '', 2: '' };
const ENV = ['RT_MINOR_KB=512', 'RT_STACK_MB=1'];
const wasi = {
	args_sizes_get(argc, size) {
		view().setUint32(argc, 1, true);
		view().setUint32(size, 7, true);
		return 0;
	},
	args_get(argv, buf) {
		view().setUint32(argv, buf, true);
		memory().set(new TextEncoder().encode('worker\0'), buf);
		return 0;
	},
	// (the runtime's sizes for a worker: jobs run GC-free or nearly, so a
	// small nursery and stack, not the 4 MB each of a program's main thread;
	// each worker's memory is its own and never shrinks)
	environ_sizes_get(n, size) {
		view().setUint32(n, ENV.length, true);
		view().setUint32(size, ENV.reduce((a, e) => a + e.length + 1, 0), true);
		return 0;
	},
	environ_get(ptrs, buf) {
		for (const e of ENV) {
			const b = new TextEncoder().encode(e + '\0');
			view().setUint32(ptrs, buf, true);
			memory().set(b, buf);
			ptrs += 4;
			buf += b.length;
		}
		return 0;
	},
	clock_res_get(id, out) {
		view().setBigUint64(out, 1000n, true);
		return 0;
	},
	clock_time_get(id, precision, out) {
		const ns = id === 0 ? BigInt(Date.now()) * 1000000n : BigInt(Math.round(performance.now() * 1e6));
		view().setBigUint64(out, ns, true);
		return 0;
	},
	random_get(p, n) {
		crypto.getRandomValues(memory().subarray(p, p + n));
		return 0;
	},
	fd_write(fd, iovs, n, written) {
		const v = view();
		let total = 0, text = '';
		for (let i = 0; i < n; i++) {
			const p = v.getUint32(iovs + 8 * i, true), len = v.getUint32(iovs + 8 * i + 4, true);
			text += new TextDecoder().decode(memory().subarray(p, p + len));
			total += len;
		}
		if (fd === 1 || fd === 2) {
			const all = lines[fd] + text, parts = all.split('\n');
			lines[fd] = parts.pop();
			for (const l of parts) (fd === 1 ? console.log : console.error)(l);
		}
		view().setUint32(written, total, true);
		return 0;
	},
	fd_prestat_get: () => 8,
	sched_yield: () => 0,
	proc_exit(code) {
		throw new Exit(code);
	},
};

const jobs = {
	worker: () => 1,
	serve(f) {
		execute = f;
	},
	start: () => 0,
	submit() {},
	cancel: () => 0,
	take() {},
	input(p) {
		if (input) memory().set(input, p);
	},
	output(status, p, n) {
		output = n >= 0 ? memory().slice(p, p + n) : null;
	},
	send(ch, p, n) {
		const bytes = memory().slice(p, p + n);
		port.postMessage({ ch, bytes }, [bytes.buffer]);
	},
	close(ch) {
		port.postMessage({ close: ch });
	},
};

listen(async (m) => {
	if (m.module) {
		try {
			const imports = { wasi_snapshot_preview1: new Proxy(wasi, { get: (o, k) => o[k] ?? (() => 52) }), helder_jobs: jobs };
			for (const i of WebAssembly.Module.imports(m.module)) {
				if (!(i.module in imports)) imports[i.module] = {};
				if (i.kind === 'function' && !(i.name in imports[i.module])) imports[i.module][i.name] = () => 0;
			}
			const instance = await WebAssembly.instantiate(m.module, imports);
			exports = instance.exports;
			try {
				exports._start();
			} catch (e) {
				if (!(e instanceof Exit)) throw e;
			}
			if (!execute) throw new Error('helder.jobs: the module serves no jobs (WebJobs is not in it)');
			port.postMessage({ ready: true });
		} catch (e) {
			port.postMessage({ failed: String(e?.stack ?? e) });
		}
		return;
	}
	input = m.input;
	output = null;
	let status;
	try {
		status = exports.__indirect_function_table.get(execute)(m.fn, input ? input.length : -1);
	} catch (e) {
		port.postMessage({ failed: String(e?.stack ?? e) });
		return;
	}
	input = null;
	const out = output;
	output = null;
	port.postMessage({ status, output: out }, out ? [out.buffer] : []);
});
