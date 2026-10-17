// Writes packages/theme/test/ref/: shadcn/ui's components as shadcn renders
// them, drawn by Chromium, one PNG per case (each component per variant,
// size, state, light and dark), and cases.json, the cases for
// FidelityTest.hx, which draws hxmc's widgets under Shadcn.sheet against
// them. The markup is what shadcn's React components (new-york-v4) render
// with Radix's attributes, its classes from src/hxmc/theme/shadcn.json
// merged as cn merges them (tailwind-merge); the CSS is Tailwind v4's for
// those classes (preflight included) with shadcn's globals.css on top (the
// tokens, the radius scale, `* { border-border }`, body's colours), Inter
// as the sans-serif font, in a page 800px wide (md: holds, as on a
// desktop). Hover, focus-visible and active are forced through the
// DevTools protocol.
//   NODE_PATH=<dir>/node_modules node packages/theme/test/ref.mjs
// (with playwright, tailwindcss@4.3.3 and tailwind-merge@3 in <dir>)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const pw = require('playwright');
const { compile } = require('tailwindcss');
const { twMerge } = require('tailwind-merge');
const sheet = JSON.parse(fs.readFileSync(path.join(here, '../src/hxmc/theme/shadcn.json'), 'utf8'));
const out = path.join(here, 'ref');

// a slot's classes: its list, cn's lists joined, or cva's base with a variant and a size
function classes(slot, variant, size) {
	const s = sheet.slots[slot];
	if (typeof s === 'string') return s;
	if (Array.isArray(s)) return twMerge(...s);
	return twMerge(s.base, s.variant?.[variant ?? 'default'] ?? '', s.size?.[size ?? 'default'] ?? '');
}
const esc = s => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const attrs = a => Object.entries(a ?? {}).map(([k, v]) => v === true ? ` ${k}` : ` ${k}="${esc(String(v))}"`).join('');
// (lucide's check, as checkbox.tsx draws it)
const check = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="size-3.5"><path d="M20 6 9 17l-5-5"/></svg>';

// each component's markup for a case (c.attrs on the element the state is on)
const markup = {
	button: c => `<button data-slot="button" data-variant="${c.variant ?? 'default'}" data-size="${c.size ?? 'default'}" class="${classes('button', c.variant, c.size)}"${attrs(c.attrs)}>${esc(c.text)}</button>`,
	badge: c => `<span data-slot="badge" data-variant="${c.variant ?? 'default'}" class="${classes('badge', c.variant)}"${attrs(c.attrs)}>${esc(c.text)}</span>`,
	input: c => `<input data-slot="input" class="${classes('input')}" placeholder="${esc(c.placeholder ?? '')}" value="${esc(c.text ?? '')}"${attrs(c.attrs)}>`,
	checkbox: c => {
		const state = c.checked ? 'checked' : 'unchecked';
		return `<button type="button" role="checkbox" aria-checked="${!!c.checked}" data-state="${state}" data-slot="checkbox" class="${classes('checkbox')}"${attrs(c.attrs)}>`
			+ (c.checked ? `<span data-state="checked" data-slot="checkbox-indicator" class="${classes('checkbox-indicator')}" style="pointer-events: none;">${check}</span>` : '') + '</button>';
	},
	switch: c => {
		const state = c.checked ? 'checked' : 'unchecked', size = c.size ?? 'default';
		return `<button type="button" role="switch" aria-checked="${!!c.checked}" data-state="${state}" data-slot="switch" data-size="${size}" class="${classes('switch')}"${attrs(c.attrs)}>`
			+ `<span data-state="${state}" data-slot="switch-thumb" class="${classes('switch-thumb')}"></span></button>`;
	},
	label: c => c.peerDisabled
		? `<div class="flex items-center gap-2">${markup.checkbox({ attrs: { disabled: true, 'data-disabled': '' } }).replace('class="', 'class="peer ')}<label data-slot="label" class="${classes('label')}">${esc(c.text)}</label></div>`
		: `<label data-slot="label" class="${classes('label')}">${esc(c.text)}</label>`,
	card: c => `<div data-slot="card" class="${classes('card')}"><div data-slot="card-header" class="${classes('card-header')}">`
		+ `<div data-slot="card-title" class="${classes('card-title')}">${esc(c.title)}</div><div data-slot="card-description" class="${classes('card-description')}">${esc(c.description)}</div>`
		+ (c.action ? `<div data-slot="card-action" class="${classes('card-action')}">${markup.button({ variant: 'link', text: c.action })}</div>` : '')
		+ `</div><div data-slot="card-content" class="${classes('card-content')}"><p>${esc(c.text)}</p></div>`
		+ `<div data-slot="card-footer" class="${classes('card-footer')}">${markup.button({ text: c.footer })}</div></div>`,
};

// the frame each component is drawn in (padding 16 around it); block: as wide as the frame
const frames = {
	button: { w: 160, h: 68 }, badge: { w: 120, h: 54 }, input: { w: 280, h: 68, block: true }, checkbox: { w: 48, h: 48 },
	switch: { w: 64, h: 51 }, label: { w: 200, h: 48 }, card: { w: 360, h: 248, block: true },
};

const cases = [];
const add = (component, name, c) => cases.push({ component, name: `${component}-${name}`, ...frames[component], ...c });
for (const dark of [false, true]) {
	const d = dark ? '-dark' : '';
	for (const variant of Object.keys(sheet.slots.button.variant)) {
		add('button', variant + d, { variant, text: 'Button', dark });
		if (variant !== 'link') add('button', `${variant}-hover${d}`, { variant, text: 'Button', dark, states: ['hover'] });
	}
	add('button', `focus${d}`, { text: 'Button', dark, states: ['focus-visible'] });
	add('button', `outline-focus${d}`, { variant: 'outline', text: 'Button', dark, states: ['focus-visible'] });
	add('button', `invalid${d}`, { variant: 'outline', text: 'Button', dark, attrs: { 'aria-invalid': 'true' } });
	add('button', `invalid-focus${d}`, { variant: 'outline', text: 'Button', dark, attrs: { 'aria-invalid': 'true' }, states: ['focus-visible'] });
	add('button', `disabled${d}`, { text: 'Button', dark, attrs: { disabled: true } });
	for (const variant of Object.keys(sheet.slots.badge.variant)) add('badge', variant + d, { variant, text: 'Badge', dark });
	add('input', `placeholder${d}`, { placeholder: 'Email', dark });
	add('input', `value${d}`, { text: 'hello@example.com', dark });
	add('input', `focus${d}`, { placeholder: 'Email', dark, states: ['focus-visible'] });
	add('input', `invalid${d}`, { text: 'not an email', dark, attrs: { 'aria-invalid': 'true' } });
	add('input', `disabled${d}`, { placeholder: 'Email', dark, attrs: { disabled: true } });
	add('checkbox', `unchecked${d}`, { dark });
	add('checkbox', `checked${d}`, { checked: true, dark });
	add('checkbox', `focus${d}`, { dark, states: ['focus-visible'] });
	add('checkbox', `disabled${d}`, { checked: true, dark, attrs: { disabled: true, 'data-disabled': '' } });
	add('checkbox', `invalid${d}`, { dark, attrs: { 'aria-invalid': 'true' } });
	for (const size of ['default', 'sm']) {
		add('switch', `unchecked-${size}${d}`, { size, dark });
		add('switch', `checked-${size}${d}`, { size, checked: true, dark });
	}
	add('switch', `focus${d}`, { checked: true, dark, states: ['focus-visible'] });
	add('switch', `disabled${d}`, { dark, attrs: { disabled: true, 'data-disabled': '' } });
	add('label', `plain${d}`, { text: 'Accept terms', dark });
	add('label', `peer-disabled${d}`, { text: 'Accept terms', dark, peerDisabled: true });
	add('card', `full${d}`, { title: 'Card Title', description: 'Card Description', action: 'Card Action', text: 'Card Content', footer: 'Card Footer', dark });
}
for (const size of Object.keys(sheet.slots.button.size)) add('button', `size-${size}`, { size, text: size.startsWith('icon') ? '+' : 'Button' });

// the CSS: Tailwind for the classes used, shadcn's globals.css (its @theme inline, tokens and base layer)
const tokens = m => Object.entries(m).map(([k, v]) => `--${k}: ${v};`).join(' ');
const input = `@import "tailwindcss";
@custom-variant dark (&:is(.dark *));
@theme inline {
	--font-sans: "Inter", sans-serif;
	--radius-sm: calc(var(--radius) * 0.6); --radius-md: calc(var(--radius) * 0.8); --radius-lg: var(--radius);
	--radius-xl: calc(var(--radius) * 1.4); --radius-2xl: calc(var(--radius) * 1.8); --radius-3xl: calc(var(--radius) * 2.2); --radius-4xl: calc(var(--radius) * 2.6);
	${Object.keys(sheet.light).map(k => `--color-${k}: var(--${k});`).join(' ')}
}
:root { --radius: ${sheet.radius}; ${tokens(sheet.light)} }
.dark { ${tokens(sheet.dark)} }
@layer base {
	* { @apply border-border outline-ring/50; }
	body { @apply bg-background text-foreground; }
}`;
const html = cases.map(c => markup[c.component](c)).join('\n');
const candidates = [...new Set([...html.matchAll(/class="([^"]*)"/g)].flatMap(m => m[1].split(/\s+/)).concat(['dark', 'bg-background']))];
const compiler = await compile(input, {
	base: here,
	loadStylesheet: async (id, base) => {
		const file = require.resolve(id === 'tailwindcss' ? 'tailwindcss/index.css' : id);
		return { path: file, base: path.dirname(file), content: fs.readFileSync(file, 'utf8') };
	},
});
const css = compiler.build(candidates);

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 800, height: 600 }, deviceScaleFactor: 1 });
const cdp = await page.context().newCDPSession(page);
for (const c of cases) {
	const align = c.block ? '' : 'display: flex; align-items: flex-start;';
	await page.setContent(`<!doctype html><html${c.dark ? ' class="dark"' : ''}><head><style>${css}</style></head>`
		+ `<body style="margin: 0"><div id="frame" class="bg-background" style="box-sizing: border-box; width: ${c.w}px; height: ${c.h}px; padding: 16px; ${align}">${markup[c.component](c)}</div></body></html>`);
	await page.evaluate(() => document.fonts.ready);
	if (c.states) {
		await cdp.send('DOM.enable');
		await cdp.send('CSS.enable');
		const { root } = await cdp.send('DOM.getDocument');
		const sel = c.component === 'label' ? '[data-slot=label]' : `[data-slot=${c.component}]`;
		const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: sel });
		await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: c.states.map(s => s === 'focus-visible' ? 'focus-visible' : s).concat(c.states.includes('focus-visible') ? ['focus'] : []) });
	}
	await page.locator('#frame').screenshot({ path: path.join(out, c.name + '.png') });
}
await browser.close();
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(cases.map(({ name, component, w, h, block, variant, size, text, placeholder, checked, dark, states, attrs, peerDisabled, title, description, action, footer }) =>
	({ name, component, w, h, block, variant, size, text, placeholder, checked, dark, states, attrs, peerDisabled, title, description, action, footer })), null, '\t') + '\n');
console.log(`ref: ${cases.length} cases in ${path.relative(process.cwd(), out)}`);
