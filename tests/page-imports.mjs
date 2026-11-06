// The browser modules a wasm32-wasi build needs, as the page helder builds
// for it chooses them (src/helder/cli/Page.hx, Page.packages): each package
// of src/helder whose imports.mjs names one of the module's import modules
// (hxmc_canvas, helder_async, ...). A test's page loads these rather than a
// list of its own, so that what the program links (a TypeScript program's
// runtime reaching helder.async's loop, say) is there as on a real page.
//
//   import { pageImports } from '../page-imports.mjs';
//   pageImports(bytes)  // ['canvas', 'async', ...]: src/helder/<p>/imports.mjs
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const helder = path.join(path.dirname(fileURLToPath(import.meta.url)), '../src/helder');

// the packages, sorted by name (Page.packages' order)
export function pageImports(wasm) {
	const names = [...new Set(WebAssembly.Module.imports(new WebAssembly.Module(wasm)).map((i) => i.module))];
	const out = [];
	for (const d of readdirSync(helder).sort()) {
		const f = path.join(helder, d, 'imports.mjs');
		if (!existsSync(f)) continue;
		const s = readFileSync(f, 'utf8');
		if (names.some((n) => new RegExp('\\b' + n + '\\b').test(s))) out.push(d);
	}
	return out;
}
