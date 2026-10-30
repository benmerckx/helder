// The JavaScript side of helder.async in the browser: the imports of the
// module "helder_async" (src/helder/async/Web.hx), for browser.mjs's option
// imports. The page's event loop turns the module's Loop: one timer at a
// time, at the earliest time the module asked for (wake, or what a turn
// returned); a turn wanted at once comes as a task of its own
// (MessageChannel, setImmediate under node), not a microtask, so that the
// page renders and handles its events between turns. Fetches end in a turn.
export default function (host) {
	let turn = 0, timer = null, due = Infinity;
	const soon = typeof setImmediate === 'function' ? setImmediate : (() => {
		const ch = new MessageChannel(), fs = [];
		ch.port1.onmessage = () => fs.shift()?.();
		return (f) => { fs.push(f); ch.port2.postMessage(0); };
	})();
	const clear = () => {
		if (timer !== null && timer !== true) clearTimeout(timer);
		timer = null;
		due = Infinity;
	};
	const run = () => {
		clear();
		if (!turn) return;
		const next = host.call(turn);
		if (next !== undefined && next >= 0) wake(next);
	};
	const wake = (seconds) => {
		const at = performance.now() + seconds * 1000;
		if (at >= due) return;
		clear();
		due = at;
		if (seconds <= 0) {
			timer = true;
			soon(() => timer === true && run());
		} else timer = setTimeout(run, seconds * 1000);
	};
	return {
		helder_async: {
			start(f) {
				turn = f;
				wake(0);
			},
			wake,
			fetch_start(p) {
				// (its body read as it arrives: loaded, and total where the
				// response says (its Content-Length, unless it is encoded:
				// that counts the encoded bytes); a turn at most every 50 ms
				// while it does, for progress)
				const f = { state: 0, body: null, loaded: 0, total: 0, abort: new AbortController() };
				const base = typeof document !== 'undefined' ? document.baseURI : host.options.base;
				let told = 0;
				fetch(new URL(host.string(p), base), { signal: f.abort.signal }).then(async (r) => {
					if (!r.ok) throw r.status;
					const length = Number(r.headers.get('content-length'));
					if (length > 0 && !r.headers.get('content-encoding')) f.total = length;
					if (!r.body || !r.body.getReader) return new Uint8Array(await r.arrayBuffer());
					const reader = r.body.getReader(), chunks = [];
					for (;;) {
						const { done, value } = await reader.read();
						if (done) break;
						chunks.push(value);
						f.loaded += value.length;
						const now = performance.now();
						if (now - told > 50) { told = now; wake(0); }
					}
					if (chunks.length == 1) return chunks[0];
					const out = new Uint8Array(f.loaded);
					let at = 0;
					for (const c of chunks) { out.set(c, at); at += c.length; }
					return out;
				}).then(
					(b) => { f.body = b; f.loaded = b.length; f.state = 1; wake(0); }, () => { f.state = -1; wake(0); });
				return host.handles.add(f);
			},
			fetch_state: (h) => host.handles.get(h).state,
			fetch_length: (h) => host.handles.get(h).body?.length ?? 0,
			fetch_loaded: (h) => host.handles.get(h).loaded,
			fetch_total: (h) => host.handles.get(h).total,
			fetch_take(h, p) {
				const f = host.handles.get(h);
				if (f.body) new Uint8Array(host.memory().buffer, p, f.body.length).set(f.body);
				host.handles.remove(h);
			},
			fetch_free(h) {
				host.handles.get(h).abort.abort();
				host.handles.remove(h);
			},
		},
	};
}
