// @hxmc/web's island loader: hydrates the <hxmc-island> elements of a static
// page (hxmc.web.Island) when each asks to be, data-load: "visible" once it
// scrolls into view, "idle" once the browser is idle, "load" at once,
// "click" on the first click or key press inside it (audio: browsers start
// it only after one; a large module: started only when asked for).
//   <script src="loader.js" defer></script>
// A JavaScript island: its bundle (data-src) is loaded once, as a script,
// then globalThis.hxmcIslands[data-island](element, props) hydrates it (the
// bundle's Islands.start put it there). A WebAssembly island: data-runner
// (@hxmc/os's browser.mjs) runs data-wasm on its canvas with data-imports
// and data-args (and data-fonts, for hxmc.text); the promise of run's result
// is hxmcWasm[id] (by the element's id), for JavaScript islands that call
// the module; hxmcWasmOptions[id], when a page or a test sets it before,
// adds to run's options (args, gfx, antialias: by default true, a
// canvas multisampled). Once it runs, the element gets
// data-gfx, the graphics API it draws with, if any. While an island starts,
// its element has data-loading; once it has started, data-hydrated and an
// hxmc:hydrated event; if it fails (main exits with an error code, or later:
// a frame that throws or exits so, a GPU device lost: the message the last
// line of its stderr; the browser refusing memory, a RangeError: "out of
// memory: ..."), data-error (the message) and an hxmc:error event.
// data-stop="offscreen" on a WebAssembly island: once it has scrolled out
// of view, its program is stopped (host.os.stop, host.gfx.release: its GPU
// memory given back), its canvas replaced by a fresh one, and the element
// waits as before (data-load) to run it again, with data-stopped and an
// hxmc:stopped event.
(() => {
	const g = globalThis, islands = g.hxmcIslands ||= {}, wasm = g.hxmcWasm ||= {}, scripts = {}, base = document.baseURI;
	const json = (s, d) => (s ? JSON.parse(s) : d);
	const script = (src) => scripts[src] ||= new Promise((ok, fail) => {
		const s = document.createElement('script');
		s.src = src;
		s.onload = ok;
		s.onerror = () => fail(new Error('hxmc: cannot load ' + src));
		document.head.append(s);
	});
	const fail = (el, e) => {
		el.removeAttribute('data-loading');
		el.setAttribute('data-error', (e && e.message) || String(e));
		el.dispatchEvent(new Event('hxmc:error'));
		console.error('hxmc: island', el, e);
	};
	async function start(el) {
		const d = el.dataset, run = (el.hxmcRun = (el.hxmcRun || 0) + 1);
		el.removeAttribute('data-stopped');
		el.removeAttribute('data-error');
		el.setAttribute('data-loading', '');
		if (d.wasm) {
			const extra = (g.hxmcWasmOptions || {})[el.id], canvas = el.querySelector('canvas');
			// (the canvas as the page wrote it: the one a stopped program's is replaced by)
			if (canvas && !el.hxmcCanvas) el.hxmcCanvas = canvas.cloneNode(false);
			// (the last line the program wrote to stderr: what a failure says,
			// unless the browser refused memory: browser.mjs's outOfMemory, or a
			// RangeError of its own, which a deep recursion's is not)
			let last = '';
			const oom = (e) => e instanceof RangeError && /memory|alloc/i.test(e.message) && !/call stack/i.test(e.message);
			const failed = (e) => new Error(e && e.outOfMemory ? e.message : oom(e) ? 'out of memory: ' + e.message : last || (e && e.message) || String(e));
			const started = import(new URL(d.runner, base).href).then((m) => m.run(new URL(d.wasm, base).href, {
				imports: json(d.imports, []), args: json(d.args, []), fonts: json(d.fonts, []), canvas, touchAction: 'pan-y', antialias: true,
				stderr: (l) => console.error((last = l)), onError: (e) => run === el.hxmcRun && fail(el, failed(e)), ...extra,
			}));
			if (el.id) wasm[el.id] = started;
			const r = await started, gfx = r && r.host && r.host.gfx;
			if (run !== el.hxmcRun) return;
			if (r && r.exitCode) throw failed('the program exited with code ' + r.exitCode);
			if (gfx && gfx.backend) el.setAttribute('data-gfx', gfx.backend);
			if (d.stop === 'offscreen') offscreen(el, r);
		} else {
			await script(new URL(d.src, base).href);
			islands[d.island](el, json(d.props, null));
		}
		el.removeAttribute('data-loading');
		el.setAttribute('data-hydrated', '');
		el.dispatchEvent(new Event('hxmc:hydrated'));
	}
	// a program stopped once its island is out of view, and the island armed again
	function offscreen(el, r) {
		const o = new IntersectionObserver((es) => {
			if (es[es.length - 1].isIntersecting) return;
			o.disconnect();
			el.hxmcRun++;
			if (r.host.os && r.host.os.stop) r.host.os.stop();
			if (r.host.gfx && r.host.gfx.release) r.host.gfx.release();
			const c = el.querySelector('canvas');
			if (c && el.hxmcCanvas) c.replaceWith(el.hxmcCanvas.cloneNode(false));
			if (el.id) delete wasm[el.id];
			for (const a of ['data-hydrated', 'data-gfx', 'data-loading', 'data-error']) el.removeAttribute(a);
			el.setAttribute('data-stopped', '');
			el.dispatchEvent(new Event('hxmc:stopped'));
			arm(el);
		}, { rootMargin: '25% 0px' });
		o.observe(el);
	}
	const when = {
		idle: (el, go) => (g.requestIdleCallback || setTimeout)(go),
		click: (el, go) => {
			const once = () => {
				el.removeEventListener('click', once);
				el.removeEventListener('keydown', once);
				go();
			};
			el.addEventListener('click', once);
			el.addEventListener('keydown', once);
		},
		visible: (el, go) => {
			const o = new IntersectionObserver((es) => {
				if (es.some((e) => e.isIntersecting)) {
					o.disconnect();
					go();
				}
			});
			o.observe(el);
		},
	};
	const arm = (el) => (when[el.dataset.load] || ((el, go) => go()))(el, () => start(el).catch((e) => fail(el, e)));
	const go = () => {
		for (const el of document.querySelectorAll('hxmc-island:not([data-hydrated])')) arm(el);
	};
	document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', go) : go();
})();
