// A demo page's numbers (site/index.tsx's DemoPage): the cells marked
// data-num="<id>[.<scene>].<key>" filled from numbers.json, which
// site/numbers.mjs measured headless in CI; "–" where it has none.
(() => {
	const cells = document.querySelectorAll('[data-num]');
	if (!cells.length) return;
	const fill = (all) => {
		for (const c of cells) {
			const key = c.dataset.num, dot = key.lastIndexOf('.');
			const row = all[key.slice(0, dot)], v = row ? row[key.slice(dot + 1)] : undefined;
			c.textContent = v === undefined || v === null ? '–' : String(v);
		}
	};
	fetch('numbers.json').then((r) => (r.ok ? r.json() : {})).then(fill, () => fill({}));
})();
