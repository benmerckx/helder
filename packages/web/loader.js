// @hxmc/web's island loader: hydrates the <hxmc-island> elements of a static
// page (hxmc.web.Island) when each asks to be, data-load: "visible" once it
// scrolls into view, "idle" once the browser is idle, "load" at once.
//   <script src="loader.js" defer></script>
// A JavaScript island: its bundle (data-src) is loaded once, as a script,
// then globalThis.hxmcIslands[data-island](element, props) hydrates it (the
// bundle's Islands.start put it there). A WebAssembly island: data-runner
// (@hxmc/os's browser.mjs) runs data-wasm on its canvas with data-imports
// and data-args; the promise of run's result is hxmcWasm[id] (by the
// element's id), for JavaScript islands that call the module. Once an
// island has started, its element gets data-hydrated and an hxmc:hydrated event.
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
	async function start(el) {
		const d = el.dataset;
		if (d.wasm) {
			const run = import(new URL(d.runner, base).href).then((m) => m.run(new URL(d.wasm, base).href, {
				imports: json(d.imports, []), args: json(d.args, []), canvas: el.querySelector('canvas'), touchAction: 'pan-y',
			}));
			if (el.id) wasm[el.id] = run;
			await run;
		} else {
			await script(new URL(d.src, base).href);
			islands[d.island](el, json(d.props, null));
		}
		el.setAttribute('data-hydrated', '');
		el.dispatchEvent(new Event('hxmc:hydrated'));
	}
	const when = {
		idle: (el, go) => (g.requestIdleCallback || setTimeout)(go),
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
	const go = () => {
		for (const el of document.querySelectorAll('hxmc-island:not([data-hydrated])'))
			(when[el.dataset.load] || ((el, go) => go()))(el, () => start(el).catch((e) => console.error('hxmc: island', el, e)));
	};
	document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', go) : go();
})();
