// Writes packages/theme/test/tailwind.txt: the CSS Tailwind v4 writes for
// each class of src/hxmc/theme/shadcn.json and its include (extras.json),
// one line per rule ("class<TAB>at-rules<TAB>selector<TAB>declarations",
// the class's selector as &, at-rules joined by " | "), the colour-mix
// fallbacks for older browsers left out (Css writes only color-mix), for
// CssTest, which compares Css.rules for each class to it.
//   NODE_PATH=<dir>/node_modules node packages/theme/test/css-ref.mjs
// (with tailwindcss@4.3.3 in <dir>)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const { compile } = require('tailwindcss');
const read = f => JSON.parse(fs.readFileSync(path.join(here, '../src/hxmc/theme', f), 'utf8'));
const sheet = read('shadcn.json');
const classes = new Set();
const walk = v => {
	if (typeof v === 'string') v.split(/\s+/).filter(Boolean).forEach(c => classes.add(c));
	else if (Array.isArray(v)) v.forEach(walk);
	else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) {
		if (k === 'states') for (const [s, cl] of Object.entries(x)) cl.split(/\s+/).filter(Boolean).forEach(c => classes.add(s + ':' + c));
		else if (k !== 'extends') walk(x);
	}
};
walk(sheet.slots);
for (const inc of sheet.include ?? []) walk(read(inc).slots);
const input = `@import "tailwindcss";
@custom-variant dark (&:is(.dark *));
@theme inline {
	--radius-sm: calc(var(--radius) * 0.6); --radius-md: calc(var(--radius) * 0.8); --radius-lg: var(--radius); --radius-xl: calc(var(--radius) * 1.4);
	${Object.keys(sheet.light).map(k => `--color-${k}: var(--${k});`).join(' ')}
}`;
const compiler = await compile(input, {
	base: here,
	loadStylesheet: async id => {
		const file = require.resolve(id === 'tailwindcss' ? 'tailwindcss/index.css' : id);
		return { path: file, base: path.dirname(file), content: fs.readFileSync(file, 'utf8') };
	},
});
const css = compiler.build([...classes]);

// (nested CSS as flat rules: at-rules, a selector, declarations)
function parse(s) {
	let i = 0;
	const skip = () => { while (i < s.length && /\s/.test(s[i])) i++; };
	function until(stops) {
		let out = '', depth = 0, q = null;
		while (i < s.length) {
			const c = s[i];
			if (q) { out += c; if (c === '\\') out += s[++i]; else if (c === q) q = null; i++; continue; }
			if (c === '"' || c === "'") q = c;
			else if (c === '\\') { out += c + s[i + 1]; i += 2; continue; }
			else if (c === '(' || c === '[') depth++;
			else if (c === ')' || c === ']') depth--;
			else if (depth === 0 && stops.includes(c)) break;
			out += c; i++;
		}
		return out.trim();
	}
	function block() {
		const items = [];
		for (;;) {
			skip();
			if (i >= s.length || s[i] === '}') { i++; return items; }
			const head = until('{;}');
			if (s[i] !== '{') { if (s[i] === ';') i++; const k = head.indexOf(':'); if (!head.startsWith('@')) items.push({ decl: [head.slice(0, k).trim(), head.slice(k + 1).trim()] }); continue; }
			i++;
			items.push({ head, body: block() });
		}
	}
	return block();
}
function flatten(items, at, sel, out) {
	const decls = items.filter(x => x.decl).map(x => x.decl);
	if (decls.length && sel) out.push({ at, sel, decls });
	for (const x of items) if (x.head) {
		if (x.head.startsWith('@layer')) flatten(x.body, at, sel, out);
		else if (x.head.startsWith('@')) flatten(x.body, at.concat([x.head]), sel, out);
		else flatten(x.body, at, sel == null ? x.head : x.head.includes('&') ? x.head.replaceAll('&', sel) : sel + ' ' + x.head, out);
	}
	return out;
}
const start = css.indexOf('@layer utilities');
const rules = flatten(parse(css.slice(css.indexOf('{', start) + 1)), [], null, []);
const lines = [];
const MIX = '@supports (color: color-mix(in lab, red, red))';
for (let k = 0; k < rules.length; k++) {
	const r = rules[k];
	const m = r.sel.match(/\.((?:\\.|[^\s.:\[>~+,()])+)/);
	if (!m) continue;
	const cls = m[1].replace(/\\(.)/g, '$1');
	// (a fallback followed by its color-mix: only the color-mix; the color-mix's own @supports left out)
	if (rules[k + 1]?.at.includes(MIX) && rules[k + 1].sel === r.sel && !r.at.includes(MIX)) continue;
	const at = r.at.filter(a => a !== MIX);
	// (every place the class is: a selector list's parts each have it)
	const esc = m[0].replace(/[.*+?^${}()|[\]\\]/g, c => '\\' + c);
	const sel = r.sel.replace(new RegExp(esc + '(?![\\w-])', 'g'), '&');
	lines.push([cls, at.join(' | '), sel, r.decls.map(([p, v]) => `${p}: ${v}`).join('; ')].join('\t'));
}
fs.writeFileSync(path.join(here, 'tailwind.txt'), lines.join('\n') + '\n');
console.log(`tailwind.txt: ${lines.length} rules of ${classes.size} classes`);
