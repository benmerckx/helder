// tests/bench/JobsWasm.hx under node: the main instance's frames at 60 fps
// (setTimeout, as requestAnimationFrame would call them) while the 4K PNG is
// decoded on the main instance between two frames (a), or in a worker
// thread's instance of the same compiled module (b': worker_threads, as a
// page's Web Worker; its own linear memory and GC heap), the pixels copied
// out of the worker's memory into an ArrayBuffer, transferred (no copy), and
// copied into the main instance's memory by the main thread, which reads
// and frees them. One line, as Jobs.hx's where it can:
//
//   jobs <variant> <frames> <median ms> <p99> <max> <GCs> <decode ms> <worker's copy-out ms> <main thread's copy-in ms> <longest task ms> <check>
//
// (decode: the worker's job, or the decode on the main instance; the
// longest task: the main thread's longest piece of work, a frame or the
// pixels' arrival. node's WASI allocates in its fast API calls, which can
// collect meanwhile and crash V8 once linear memory is large: hence no fast
// calls)
//
//   node --no-turbo-fast-api-calls --stack-size=65500 tests/bench/jobs.mjs <JobsWasm.wasm> <DejaVuSans.ttf> <photo.png> <a|b|none>
import fs from 'node:fs';
import process from 'node:process';
import { WASI } from 'node:wasi';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';

const WARM = 60, WINDOW = 90, FRAME = 1000 / 60;

// an instance of the module, its program started with these arguments; hxmc_jobs's imports `jobs`
async function instance(module, args, jobs) {
	const wasi = new WASI({ version: 'preview1', args, env: process.env, preopens: { '.': '.' }, returnOnExit: true });
	const imports = wasi.getImportObject();
	imports.hxmc_jobs = jobs;
	for (const i of WebAssembly.Module.imports(module)) {
		if (!(i.module in imports)) imports[i.module] = {};
		if (i.kind === 'function' && !(i.name in imports[i.module])) imports[i.module][i.name] = () => 0;
	}
	const inst = await WebAssembly.instantiate(module, imports);
	const code = wasi.start(inst);
	if (code) throw new Error(`exit code ${code}`);
	return inst.exports;
}

if (!isMainThread) {
	// the worker: its instance, then each job as asked
	const { module, args } = workerData;
	let job, length;
	const ex = await instance(module, args, { worker: (j, l) => { job = j; length = l; } });
	const table = ex.__indirect_function_table;
	parentPort.on('message', () => {
		const t0 = performance.now();
		const p = table.get(job)(), n = table.get(length)();
		const t1 = performance.now();
		const px = new Uint8Array(ex.memory.buffer, p, n).slice();
		const t2 = performance.now();
		parentPort.postMessage({ px: px.buffer, decode: t1 - t0, copyOut: t2 - t1 }, [px.buffer]);
	});
	parentPort.postMessage('ready');
} else {
	const [file, font, png, variant] = process.argv.slice(2);
	const module = await WebAssembly.compile(fs.readFileSync(file));
	let cb;
	const ex = await instance(module, [file, font, png, 'main'], { main: (frame, here, collections, alloc, take) => { cb = { frame, here, collections, alloc, take }; } });
	const call = (f, ...a) => ex.__indirect_function_table.get(f)(...a);
	let worker = null;
	if (variant === 'b') {
		worker = new Worker(new URL(import.meta.url), { workerData: { module, args: [file, font, png, 'worker'] }, resourceLimits: { stackSizeMb: 64 } });
		await new Promise((ok) => worker.once('message', ok));
	}
	const times = [];
	let gcs = 0, decode = 0, copyOut = 0, copyIn = 0, longest = 0, check = 0, back = variant === 'none', k = 0;
	if (worker)
		worker.on('message', (m) => {
			// (the pixels' arrival: into the main instance's memory, read, freed)
			const t0 = performance.now(), n = m.px.byteLength, p = call(cb.alloc, n);
			new Uint8Array(ex.memory.buffer, p, n).set(new Uint8Array(m.px));
			check += call(cb.take, p, n);
			copyIn = performance.now() - t0;
			longest = Math.max(longest, copyIn);
			decode = m.decode;
			copyOut = m.copyOut;
			back = true;
		});
	let next = performance.now();
	await new Promise((done) => {
		function tick() {
			const c0 = call(cb.collections), t0 = performance.now();
			call(cb.frame);
			if (k === WARM) {
				if (variant === 'a') {
					check += call(cb.here);
					decode = performance.now() - t0;
					back = true;
				} else if (worker) worker.postMessage('go');
			}
			const t = performance.now() - t0;
			if (k >= WARM) {
				times.push(t);
				gcs += call(cb.collections) - c0;
				longest = Math.max(longest, t);
			}
			k++;
			if (k >= WARM + WINDOW && back) return done();
			next += FRAME;
			setTimeout(tick, Math.max(0, next - performance.now()));
		}
		tick();
	});
	if (worker) await worker.terminate();
	const sorted = times.slice().sort((a, b) => a - b), at = (q) => sorted[Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1)];
	const f = (v) => String(Math.round(v * 1000) / 1000);
	console.log(['jobs', variant, times.length, f(at(0.5)), f(at(0.99)), f(sorted[sorted.length - 1]), gcs, f(decode), f(copyOut), f(copyIn), f(longest), check].join(' '));
}
