// helder.compiler.web's page side: the compiler worker's protocol
// (protocol.d.ts) as promises.
//
//   import { CompilerClient } from './client.mjs';
//   const c = new CompilerClient(new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' }));
//   await c.init();
//   await c.write({ '/work/app/main.tsx': text });
//   const b = await c.build('/work/app');          // {ok, diagnostics, wasm, ...}
//   c.running = (request) => preview.devtools(request); // edits' patches reach the preview
//   const e = await c.edit({ '/work/app/main.tsx': saved }); // patched, unchanged or build
//
// running: (request) => response | null | Promise of one; the preview's
// answer to a devtools request (Hot.literals, Runtime.reload), null when
// none runs. Unset: every edit is a build's.
export const PROTOCOL = 1;

export class CompilerClient {
	constructor(worker) {
		this.worker = worker;
		this.next = 1;
		this.pending = new Map();
		this.running = null;
		this.onLog = (text) => console.log(text);
		this.onProgress = null;
		worker.addEventListener('message', (e) => this.receive(e.data));
		worker.addEventListener('error', (e) => {
			const err = new Error('the compiler worker failed: ' + (e.message ?? e));
			for (const p of this.pending.values()) p.reject(err);
			this.pending.clear();
		});
	}

	receive(m) {
		if (m.type === 'result' || m.type === 'error') {
			const p = this.pending.get(m.id);
			if (!p) return;
			this.pending.delete(m.id);
			if (m.type === 'result') p.resolve(m.result);
			else p.reject(new Error(m.message));
		} else if (m.type === 'log') this.onLog?.(m.text);
		else if (m.type === 'progress') this.onProgress?.(m);
		else if (m.type === 'running') {
			const answer = (response) => this.worker.postMessage({ type: 'running', rid: m.rid, response: response ?? null });
			if (!this.running) return answer(null);
			Promise.resolve().then(() => this.running(m.request)).then(answer, (err) => answer({ error: { code: -32603, message: String(err?.message ?? err) } }));
		}
	}

	request(type, body = {}, transfer = []) {
		const id = this.next++;
		return new Promise((resolve, reject) => {
			this.pending.set(id, { resolve, reject });
			this.worker.postMessage({ ...body, type, id }, transfer);
		});
	}

	init(options = {}) { return this.request('init', options); }
	write(files) { return this.request('write', { files }); }
	read(path) { return this.request('read', { path }); }
	list(dir) { return this.request('list', { dir }); }
	check(entry, options = {}) { return this.request('check', { entry, ...options }); }
	build(entry, options = {}) { return this.request('build', { entry, ...options }); }
	invalidate(files) { return this.request('invalidate', { files }); }
	edit(files, options = {}) { return this.request('edit', { files, ...options }); }
	reload(params) { return this.request('reload', { params }); }
	stats() { return this.request('stats'); }
	terminate() { this.worker.terminate(); }
}
