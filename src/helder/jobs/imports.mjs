// The page's side of helder.jobs on WebAssembly: the imports of the module
// "helder_jobs" (src/helder/jobs/WebJobs.hx), for browser.mjs's option
// imports (and helder.test's wasi.mjs under node). Jobs run in Web Workers
// (node: worker_threads), each instantiating the program's own compiled
// module (host.module, posted: compiled once) with worker.mjs's small WASI;
// a job is its callback's index in the function table, the same in every
// instance. Inputs and outputs are copied out of one instance's memory into
// an ArrayBuffer, transferred (no copy), and copied into the other's: no
// SharedArrayBuffer, no cross-origin isolation. Workers start as jobs come,
// up to the number asked for (or the cores but one); without Worker, or
// without host.module, start answers 0 and the program runs jobs itself.
// A cancelled job is dropped if it is queued; if it runs, its worker is
// ended (a running instance sees no messages) and another made when needed.
export default async function (host) {
	const node = typeof process !== 'undefined' && !!process.versions?.node && typeof document === 'undefined';
	const threads = node ? await import('node:worker_threads') : null;
	const cores = node ? (await import('node:os')).availableParallelism() : (globalThis.navigator?.hardwareConcurrency ?? 2);
	const url = new URL('./worker.mjs', import.meta.url);
	let arrived = 0, size = 0, current = null;
	const workers = [], queue = [];

	// a worker: its instance made, then one job at a time
	function spawn() {
		const w = { job: null, ready: false, port: null };
		const on = (m) => {
			if (m.ready) {
				w.ready = true;
				return pump();
			}
			if (m.ch !== undefined) return deliver(1, m.ch, 0, m.bytes);
			if (m.close !== undefined) return deliver(2, m.close, 0, null);
			if (m.failed) {
				// (its instance did not start, or a job trapped: it is ended, the job failed)
				end(w);
				if (w.job) deliver(0, w.job.id, -1, error(m.failed));
				w.job = null;
				return pump();
			}
			const id = w.job.id;
			w.job = null;
			deliver(0, id, m.status, m.output);
			pump();
		};
		if (node) {
			w.port = new threads.Worker(url, { resourceLimits: { stackSizeMb: 64 } });
			w.port.on('message', on);
			w.port.on('error', (e) => on({ failed: String(e) }));
		} else {
			w.port = new Worker(url, { type: 'module' });
			w.port.onmessage = (e) => on(e.data);
			w.port.onerror = (e) => on({ failed: e.message ?? 'worker error' });
		}
		w.port.postMessage({ module: host.module });
		workers.push(w);
	}

	function end(w) {
		w.port.terminate();
		const i = workers.indexOf(w);
		if (i >= 0) workers.splice(i, 1);
	}

	// the queued jobs to the idle workers; workers made while jobs wait
	function pump() {
		for (const w of workers) {
			if (queue.length === 0) break;
			if (!w.ready || w.job) continue;
			w.job = queue.shift();
			const input = w.job.input;
			w.port.postMessage({ fn: w.job.fn, input }, input ? [input.buffer] : []);
		}
		// (node: a worker with a job keeps the process, an idle one not)
		if (node) for (const w of workers) w.job || (!w.ready && queue.length) ? w.port.ref() : w.port.unref();
		let free = workers.filter((w) => !w.job).length;
		while (queue.length > free && workers.length < size) {
			spawn();
			free++;
		}
	}

	// (a result, a channel's message or close into the module: arrived takes the bytes)
	function deliver(kind, id, status, bytes) {
		current = bytes ? new Uint8Array(bytes.buffer ?? bytes, bytes.byteOffset ?? 0, bytes.byteLength) : null;
		host.call(arrived, kind, id, status, current ? current.length : -1);
		current = null;
	}

	// (a worker's failure as a GC job's: its message, as helder.jobs' Writer writes a String)
	function error(message) {
		const s = new TextEncoder().encode(message), b = new Uint8Array(4 + s.length);
		new DataView(b.buffer).setInt32(0, s.length, true);
		b.set(s, 4);
		return b;
	}

	return {
		helder_jobs: {
			worker: () => 0,
			serve() {},
			start(f, wanted) {
				arrived = f;
				const can = node || typeof Worker !== 'undefined';
				size = !can || !host.module ? 0 : wanted >= 0 ? wanted : Math.max(1, cores - 1);
				return size;
			},
			submit(id, fn, p, n) {
				queue.push({ id, fn, input: n >= 0 ? host.bytes(p, n).slice() : null });
				pump();
			},
			cancel(id) {
				const q = queue.findIndex((j) => j.id === id);
				if (q >= 0) {
					queue.splice(q, 1);
					return 1;
				}
				const w = workers.find((w) => w.job?.id === id);
				if (!w) return 0;
				end(w);
				pump();
				return 1;
			},
			take(p) {
				if (current) host.bytes(p, current.length).set(current);
			},
			input() {},
			output() {},
			send() {},
			close() {},
		},
	};
}
