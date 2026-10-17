// The weight of each page of a built site (`make site` prints it): what a
// visit loads at first (the page, its stylesheet, the loader and the
// islands it starts at once or when idle) and what its other islands load
// once they scroll into view or are clicked (their bundles, modules,
// imports and fonts), in bytes and gzipped. Files shared by the pages count
// on each.
//   node site/tools/weights.mjs bin/site [--json]
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import path from 'node:path';

const dir = process.argv[2];
const sizes = new Map();
function size(file) {
	if (!sizes.has(file)) {
		const p = path.join(dir, file);
		if (!existsSync(p)) return sizes.set(file, null).get(file);
		const b = readFileSync(p);
		sizes.set(file, { raw: b.length, gz: gzipSync(b, { level: 9 }).length });
	}
	return sizes.get(file);
}

function pages(d, rel = '') {
	const out = [];
	for (const n of readdirSync(path.join(dir, rel)).sort()) {
		const r = rel ? `${rel}/${n}` : n;
		if (statSync(path.join(dir, r)).isDirectory()) out.push(...pages(d, r));
		else if (n.endsWith('.html')) out.push(r);
	}
	return out;
}

// a page's address of a file, as a path in the site (no query)
const local = (page, url) => {
	if (/^[a-z]+:/.test(url)) return null;
	return path.posix.normalize(path.posix.join(path.posix.dirname(page), url.split('?')[0].split('#')[0]));
};
const attr = (tag, name) => {
	const m = tag.match(new RegExp(`\\s${name}="([^"]*)"`));
	return m ? m[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&') : null;
};

const report = [];
for (const page of pages(dir)) {
	const html = readFileSync(path.join(dir, page), 'utf8');
	const first = new Set([page]), later = new Set();
	for (const m of html.matchAll(/<link\b[^>]*>/g)) if (attr(m[0], 'rel') === 'stylesheet') first.add(local(page, attr(m[0], 'href')));
	for (const m of html.matchAll(/<script\b[^>]*>/g)) { const s = attr(m[0], 'src'); if (s) first.add(local(page, s)); }
	for (const m of html.matchAll(/<hxmc-island\b[^>]*>/g)) {
		const load = attr(m[0], 'data-load');
		const set = load === 'load' || load === 'idle' ? first : later;
		const files = [attr(m[0], 'data-src'), attr(m[0], 'data-wasm'), attr(m[0], 'data-runner')];
		for (const k of ['data-imports', 'data-fonts']) { const v = attr(m[0], k); if (v) files.push(...JSON.parse(v)); }
		for (const f of files) if (f) { const l = local(page, f); if (!first.has(l)) set.add(l); }
	}
	const sum = (s) => [...s].reduce((a, f) => { const z = size(f); return z ? { raw: a.raw + z.raw, gz: a.gz + z.gz } : a; }, { raw: 0, gz: 0 });
	report.push({ page, first: sum(first), later: sum(later), html: size(page) });
}

if (process.argv.includes('--json')) console.log(JSON.stringify(report, null, 1));
else {
	const kb = (n) => (n / 1024).toFixed(n < 10240 ? 1 : 0) + ' KB';
	const w = Math.max(...report.map((r) => r.page.length));
	console.log(`${'page'.padEnd(w)}  ${'first load (gzip)'.padStart(22)}  ${'lazy islands (gzip)'.padStart(24)}`);
	for (const r of report)
		console.log(`${r.page.padEnd(w)}  ${(kb(r.first.raw) + ' (' + kb(r.first.gz) + ')').padStart(22)}  ${(r.later.raw ? kb(r.later.raw) + ' (' + kb(r.later.gz) + ')' : '-').padStart(24)}`);
}
