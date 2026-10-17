// Writes packages/theme/test/ref/: shadcn/ui's components as shadcn renders
// them, drawn by Chromium, one PNG per case (each component per variant,
// size, state, light and dark), and cases.json, the cases for
// FidelityTest.hx, which draws hxmc's widgets under Shadcn.sheet against
// them. The markup is what shadcn's React components (new-york-v4) render
// with Radix's attributes (popups open in place, as their content renders),
// their classes from src/hxmc/theme/shadcn.json merged as cn merges them
// (tailwind-merge); the CSS is Tailwind v4's for those classes (preflight
// included) with shadcn's globals.css on top (the tokens, the radius scale,
// `* { border-border }`, body's colours), Inter as the sans-serif font,
// animations off, in a page 800px wide (md: holds, as on a desktop). Hover,
// focus-visible and active are forced through the DevTools protocol.
// Calendar and sonner's toast have no case yet (react-day-picker's and
// sonner's own markup and CSS).
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

// a slot's classes as Tw.sheet reads them: a list, cn's lists, cva's base
// with a variant and a size (or another slot's), then the entry's class
function lists(s, variant, size) {
	if (typeof s === 'string') return [s];
	if (Array.isArray(s)) return s;
	if (s.extends) {
		const fixed = s.variant != null || s.size != null;
		return lists(sheet.slots[s.extends], fixed ? s.variant ?? 'default' : variant, fixed ? s.size ?? 'default' : size).concat(s.class ?? []);
	}
	return [].concat(s.base, s.variant?.[variant ?? 'default'] ?? [], s.size?.[size ?? 'default'] ?? [], s.class ?? []);
}
const classes = (slot, variant, size) => twMerge(...lists(sheet.slots[slot], variant, size));
const esc = s => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const attrs = a => Object.entries(a ?? {}).map(([k, v]) => v === true ? ` ${k}` : ` ${k}="${esc(String(v))}"`).join('');
// an element of a slot: <tag data-slot class attrs>inner</tag>
const el = (tag, slot, inner = '', a = {}, variant, size) => `<${tag} data-slot="${slot}" class="${classes(slot, variant, size)}"${attrs(a)}>${inner}</${tag}>`;
// lucide's icons, as the components draw them
const ICONS = {
	check: '<path d="M20 6 9 17l-5-5"/>', circle: '<circle cx="12" cy="12" r="10"/>', 'chevron-down': '<path d="m6 9 6 6 6-6"/>',
	'chevron-right': '<path d="m9 18 6-6-6-6"/>', 'chevron-left': '<path d="m15 18-6-6 6-6"/>',
	more: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
};
const icon = (name, cls = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="${cls}">${ICONS[name]}</svg>`;
const state = on => on ? 'checked' : 'unchecked';

// each component's markup for a case (c.attrs on the element the state is on)
const markup = {
	button: c => `<button data-slot="button" data-variant="${c.variant ?? 'default'}" data-size="${c.size ?? 'default'}" class="${classes('button', c.variant, c.size)}"${attrs(c.attrs)}>${esc(c.text)}</button>`,
	badge: c => `<span data-slot="badge" data-variant="${c.variant ?? 'default'}" class="${classes('badge', c.variant)}"${attrs(c.attrs)}>${esc(c.text)}</span>`,
	input: c => `<input data-slot="input" class="${classes('input')}" placeholder="${esc(c.placeholder ?? '')}" value="${esc(c.text ?? '')}"${attrs(c.attrs)}>`,
	textarea: c => el('textarea', 'textarea', esc(c.text ?? ''), { placeholder: c.placeholder ?? '', ...c.attrs }),
	checkbox: c => el('button', 'checkbox', c.checked ? el('span', 'checkbox-indicator', icon('check', 'size-3.5'), { 'data-state': 'checked', style: 'pointer-events: none;' }) : '',
		{ type: 'button', role: 'checkbox', 'aria-checked': !!c.checked, 'data-state': state(c.checked), ...c.attrs }),
	switch: c => el('button', 'switch', el('span', 'switch-thumb', '', { 'data-state': state(c.checked) }),
		{ type: 'button', role: 'switch', 'aria-checked': !!c.checked, 'data-state': state(c.checked), 'data-size': c.size ?? 'default', ...c.attrs }),
	label: c => c.peerDisabled
		? `<div class="flex items-center gap-2">${markup.checkbox({ attrs: { disabled: true, 'data-disabled': '' } }).replace('class="', 'class="peer ')}${el('label', 'label', esc(c.text))}</div>`
		: el('label', 'label', esc(c.text)),
	card: c => el('div', 'card', el('div', 'card-header', el('div', 'card-title', esc(c.title)) + el('div', 'card-description', esc(c.description))
		+ (c.action ? el('div', 'card-action', markup.button({ variant: 'link', text: c.action })) : ''))
		+ el('div', 'card-content', `<p>${esc(c.text)}</p>`) + el('div', 'card-footer', markup.button({ text: c.footer }))),
	'radio-group': c => el('div', 'radio-group', ['Default', 'Comfortable'].map((t, i) => {
		const on = i === (c.value ?? 0);
		const item = el('button', 'radio-group-item', on ? el('span', 'radio-group-indicator', icon('circle', classes('radio-group-icon')), { 'data-state': 'checked' }) : '',
			{ type: 'button', role: 'radio', 'aria-checked': on, 'data-state': state(on), id: `r${i}`, ...(i === 0 ? c.attrs : {}) });
		return `<div class="flex items-center gap-3">${item}${el('label', 'label', t, { for: `r${i}` })}</div>`;
	}).join(''), { role: 'radiogroup' }),
	slider: c => {
		const v = c.value ?? 50;
		return el('span', 'slider', el('span', 'slider-track', el('span', 'slider-range', '', { 'data-orientation': 'horizontal', style: `left: 0%; right: ${100 - v}%;` }), { 'data-orientation': 'horizontal' })
			+ `<span style="transform: translateX(-50%); position: absolute; left: calc(${v}% + ${8 - v * 0.16}px);">` + el('span', 'slider-thumb', '', { role: 'slider', tabindex: 0, 'data-orientation': 'horizontal', ...c.attrs }) + '</span>',
			{ 'data-orientation': 'horizontal', dir: 'ltr' });
	},
	tabs: c => el('div', 'tabs', el('div', 'tabs-list', ['Account', 'Password'].map((t, i) =>
		el('button', 'tabs-trigger', t, { type: 'button', role: 'tab', 'data-state': i === 0 ? 'active' : 'inactive', 'data-orientation': 'horizontal', ...(i === 0 ? c.attrs : {}) })).join(''),
		{ role: 'tablist', 'data-variant': c.variant ?? 'default', 'data-orientation': 'horizontal' }, c.variant)
		+ el('div', 'tabs-content', 'Make changes to your account here.', { role: 'tabpanel', 'data-state': 'active', 'data-orientation': 'horizontal' }),
		{ 'data-orientation': 'horizontal', dir: 'ltr' }),
	progress: c => el('div', 'progress', el('div', 'progress-indicator', '', { style: `transform: translateX(-${100 - c.value}%);` }), { role: 'progressbar' }),
	separator: c => `<div><div class="text-sm leading-none font-medium">Radix Primitives</div>${el('div', 'separator', '', { 'data-orientation': 'horizontal', role: 'none' }).replace('class="', 'class="my-4 ')}<div class="text-sm">Blog</div></div>`,
	skeleton: c => `<div class="flex items-center gap-4">${el('div', 'skeleton').replace('class="', 'class="size-12 rounded-full ')}<div class="space-y-2">${el('div', 'skeleton').replace('class="', 'class="h-4 w-[200px] ')}${el('div', 'skeleton').replace('class="', 'class="h-4 w-[150px] ')}</div></div>`,
	toggle: c => el('button', 'toggle', esc(c.text), { type: 'button', 'aria-pressed': !!c.on, 'data-state': c.on ? 'on' : 'off', ...c.attrs }, c.variant, c.size),
	'toggle-group': c => el('div', 'toggle-group', ['Bold', 'Italic', 'Underline'].map((t, i) =>
		el('button', 'toggle-group-item', t, { type: 'button', role: 'radio', 'data-state': i === 1 ? 'on' : 'off', 'data-variant': c.variant ?? 'default', 'data-size': 'default', 'data-spacing': 0 }, c.variant)).join(''),
		{ role: 'group', 'data-variant': c.variant ?? 'default', 'data-size': 'default', 'data-spacing': 0, style: '--gap: 0;' }),
	alert: c => el('div', 'alert', el('div', 'alert-title', esc(c.title)) + el('div', 'alert-description', esc(c.text)), { role: 'alert' }, c.variant),
	select: c => el('button', 'select-trigger', `<span data-slot="select-value" style="pointer-events: none;">${esc(c.text ?? c.placeholder)}</span>${icon('chevron-down', classes('select-trigger-icon'))}`,
		{ type: 'button', role: 'combobox', 'data-state': 'closed', 'data-size': 'default', ...(c.text ? {} : { 'data-placeholder': '' }), ...c.attrs }),
	'select-content': c => el('div', 'select-content', el('div', 'select-viewport', el('div', 'select-label', 'Fruits')
		+ ['Apple', 'Banana', 'Blueberry'].map((t, i) => el('div', 'select-item', (i === 0 ? el('span', 'select-item-indicator', icon('check', 'size-4')) : '') + `<span>${t}</span>`,
			{ role: 'option', ...(i === 1 ? { 'data-highlighted': '' } : {}) })).join('')
		+ el('div', 'select-separator') + el('div', 'select-item', '<span>Grapes</span>', { role: 'option', 'data-disabled': '' })), { role: 'listbox', 'data-state': 'open' }),
	table: c => el('div', 'table-container', el('table', 'table', el('thead', 'table-header', el('tr', 'table-row', ['Invoice', 'Status', 'Amount'].map(t => el('th', 'table-head', t)).join('')))
		+ el('tbody', 'table-body', [['INV001', 'Paid', '$250.00'], ['INV002', 'Pending', '$150.00'], ['INV003', 'Unpaid', '$350.00']].map((r, i) =>
			el('tr', 'table-row', r.map(t => el('td', 'table-cell', t)).join(''), i === 1 ? { 'data-state': 'selected' } : {})).join('')))),
	accordion: c => `<div data-slot="accordion" data-orientation="vertical">${[['Product Information', 'Our flagship product combines cutting-edge technology with sleek design.'], ['Shipping Details', 'We offer worldwide shipping.']].map(([t, body], i) => {
		const open = i === 0;
		return el('div', 'accordion-item', `<h3 data-orientation="vertical" data-state="${open ? 'open' : 'closed'}" class="flex">`
			+ el('button', 'accordion-trigger', t + icon('chevron-down', classes('accordion-trigger-icon')), { type: 'button', 'aria-expanded': open, 'data-state': open ? 'open' : 'closed', ...(i === 0 ? c.attrs : {}) }) + '</h3>'
			+ (open ? `<div data-slot="accordion-content" data-state="open" role="region" class="${twMerge(sheet.slots['accordion-content'][0])}"><div class="${sheet.slots['accordion-content'][1]}">${body}</div></div>` : ''),
			{ 'data-state': open ? 'open' : 'closed', 'data-orientation': 'vertical' });
	}).join('')}</div>`,
	breadcrumb: c => `<nav aria-label="breadcrumb" data-slot="breadcrumb">${el('ol', 'breadcrumb-list',
		el('li', 'breadcrumb-item', el('a', 'breadcrumb-link', 'Home', { href: '#' })) + el('li', 'breadcrumb-separator', icon('chevron-right'), { role: 'presentation', 'aria-hidden': 'true' })
		+ el('li', 'breadcrumb-item', el('span', 'breadcrumb-ellipsis', icon('more', 'size-4'), { role: 'presentation', 'aria-hidden': 'true' })) + el('li', 'breadcrumb-separator', icon('chevron-right'), { role: 'presentation', 'aria-hidden': 'true' })
		+ el('li', 'breadcrumb-item', el('span', 'breadcrumb-page', 'Breadcrumb', { role: 'link', 'aria-disabled': 'true', 'aria-current': 'page' })))}</nav>`,
	pagination: c => el('nav', 'pagination', el('ul', 'pagination-content',
		`<li data-slot="pagination-item">${el('a', 'pagination-previous', icon('chevron-left') + '<span class="hidden sm:block">Previous</span>', { href: '#', 'aria-label': 'Go to previous page' }).replace('data-slot="pagination-previous"', 'data-slot="pagination-link"')}</li>`
		+ [1, 2, 3].map(n => `<li data-slot="pagination-item">${el('a', 'pagination-link', n, { href: '#', ...(n === 2 ? { 'aria-current': 'page', 'data-active': 'true' } : {}) }, n === 2 ? 'outline' : 'ghost', 'icon')}</li>`).join('')
		+ `<li data-slot="pagination-item">${el('span', 'pagination-ellipsis', icon('more', 'size-4'), { 'aria-hidden': true })}</li>`
		+ `<li data-slot="pagination-item">${el('a', 'pagination-next', '<span class="hidden sm:block">Next</span>' + icon('chevron-right'), { href: '#', 'aria-label': 'Go to next page' }).replace('data-slot="pagination-next"', 'data-slot="pagination-link"')}</li>`),
		{ role: 'navigation', 'aria-label': 'pagination' }),
	dialog: c => el('div', 'dialog-overlay', '', { 'data-state': 'open' }) + el('div', 'dialog-content',
		el('div', 'dialog-header', el('h2', 'dialog-title', 'Edit profile') + el('p', 'dialog-description', "Make changes to your profile here. Click save when you're done."))
		+ el('div', 'dialog-footer', markup.button({ variant: 'outline', text: 'Cancel' }) + markup.button({ text: 'Save changes' }))
		+ el('button', 'dialog-close', '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>', { type: 'button' }),
		{ role: 'dialog', 'data-state': 'open' }),
	popover: c => el('div', 'popover-content', el('div', 'popover-header', el('div', 'popover-title', 'Dimensions') + el('div', 'popover-description', 'Set the dimensions for the layer.')), { 'data-state': 'open', 'data-side': 'bottom' }),
	tooltip: c => el('div', 'tooltip-content', 'Add to library', { 'data-state': 'delayed-open', 'data-side': 'top' }),
	'dropdown-menu': c => el('div', 'dropdown-menu-content', el('div', 'dropdown-menu-label', 'My Account') + el('div', 'dropdown-menu-separator', '', { role: 'separator' })
		+ el('div', 'dropdown-menu-item', 'Profile' + el('span', 'dropdown-menu-shortcut', '⇧⌘P'), { role: 'menuitem', 'data-variant': 'default' })
		+ el('div', 'dropdown-menu-item', 'Billing' + el('span', 'dropdown-menu-shortcut', '⌘B'), { role: 'menuitem', 'data-variant': 'default', 'data-highlighted': '' }).replace('data-highlighted=""', 'data-highlighted="" data-force-focus')
		+ el('div', 'dropdown-menu-checkbox-item', `<span class="${sheet.slots['dropdown-menu-item-indicator']}">${icon('check', 'size-4')}</span>Status Bar`, { role: 'menuitemcheckbox', 'aria-checked': 'true', 'data-state': 'checked' })
		+ el('div', 'dropdown-menu-item', 'Delete', { role: 'menuitem', 'data-variant': 'destructive' }, 'destructive')
		+ el('div', 'dropdown-menu-item', 'Disabled', { role: 'menuitem', 'data-variant': 'default', 'data-disabled': '' }), { role: 'menu', 'data-state': 'open', 'data-side': 'bottom' }),
	menubar: c => el('div', 'menubar', ['File', 'Edit', 'View'].map((t, i) => el('button', 'menubar-trigger', t, { type: 'button', role: 'menuitem', 'data-state': i === 0 ? 'open' : 'closed' })).join(''), { role: 'menubar' }),
	command: c => el('div', 'command', el('div', 'command-input-wrapper', '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="size-4 shrink-0 opacity-50"><path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/></svg>'
		+ `<input data-slot="command-input" class="${classes('command-input')}" placeholder="Type a command or search...">`)
		+ el('div', 'command-list', el('div', 'command-group', ['Calendar', 'Search Emoji', 'Calculator'].map((t, i) => el('div', 'command-item', t, { role: 'option', 'data-selected': i === 0 ? 'true' : 'false', 'data-disabled': i === 2 ? 'true' : 'false' })).join(''), { role: 'presentation' })
			+ el('div', 'command-separator', '', { role: 'separator' })
			+ el('div', 'command-group', el('div', 'command-item', 'Settings' + el('span', 'command-shortcut', '⌘S'), { role: 'option', 'data-selected': 'false', 'data-disabled': 'false' })), { role: 'listbox' }))
		.replace('class="', 'class="rounded-lg border shadow-md md:min-w-[450px] '),
};

// the frame each component is drawn in (padding 16 around it); block: as wide as the frame
const frames = {
	button: { w: 160, h: 68 }, badge: { w: 120, h: 54 }, input: { w: 280, h: 68, block: true }, checkbox: { w: 48, h: 48 },
	switch: { w: 64, h: 51 }, label: { w: 200, h: 48 }, card: { w: 360, h: 248, block: true }, textarea: { w: 280, h: 96, block: true },
	'radio-group': { w: 180, h: 76 }, slider: { w: 240, h: 48, block: true }, tabs: { w: 320, h: 112 }, progress: { w: 240, h: 40, block: true },
	separator: { w: 240, h: 92, block: true }, skeleton: { w: 300, h: 80 }, toggle: { w: 120, h: 68 }, 'toggle-group': { w: 280, h: 68 },
	alert: { w: 400, h: 116, block: true }, select: { w: 220, h: 68 }, 'select-content': { w: 200, h: 200 }, table: { w: 360, h: 200, block: true },
	accordion: { w: 400, h: 200, block: true }, breadcrumb: { w: 300, h: 52 }, pagination: { w: 420, h: 68, block: true }, dialog: { w: 800, h: 600 },
	popover: { w: 320, h: 120 }, tooltip: { w: 160, h: 60 }, 'dropdown-menu': { w: 240, h: 240 }, menubar: { w: 240, h: 68 }, command: { w: 482, h: 240 },
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
	add('textarea', `placeholder${d}`, { placeholder: 'Type your message here.', dark });
	add('textarea', `focus${d}`, { placeholder: 'Type your message here.', dark, states: ['focus-visible'] });
	add('textarea', `invalid${d}`, { text: 'Too short', dark, attrs: { 'aria-invalid': 'true' } });
	add('radio-group', `default${d}`, { dark });
	add('radio-group', `focus${d}`, { dark, states: ['focus-visible'] });
	add('slider', `default${d}`, { value: 50, dark });
	add('slider', `hover${d}`, { value: 30, dark, states: ['hover'] });
	add('tabs', `default${d}`, { dark });
	add('tabs', `line${d}`, { variant: 'line', dark });
	add('tabs', `focus${d}`, { dark, states: ['focus-visible'] });
	add('progress', `60${d}`, { value: 60, dark });
	add('separator', `horizontal${d}`, { dark });
	add('skeleton', `default${d}`, { dark });
	for (const variant of ['default', 'outline']) {
		add('toggle', `${variant}-off${d}`, { variant, text: 'Bold', dark });
		add('toggle', `${variant}-on${d}`, { variant, text: 'Bold', on: true, dark });
		add('toggle', `${variant}-hover${d}`, { variant, text: 'Bold', dark, states: ['hover'] });
	}
	add('toggle-group', `outline${d}`, { variant: 'outline', dark });
	add('toggle-group', `default${d}`, { dark });
	for (const variant of ['default', 'destructive']) add('alert', variant + d, { variant, title: 'Heads up!', text: 'You can add components to your app using the cli.', dark });
	add('select', `placeholder${d}`, { placeholder: 'Select a fruit', dark });
	add('select', `value${d}`, { text: 'Apple', dark });
	add('select', `focus${d}`, { text: 'Apple', dark, states: ['focus-visible'] });
	add('select-content', `open${d}`, { dark });
	add('table', `default${d}`, { dark });
	add('accordion', `default${d}`, { dark });
	add('breadcrumb', `default${d}`, { dark });
	add('pagination', `default${d}`, { dark });
	add('dialog', `open${d}`, { dark });
	add('popover', `open${d}`, { dark });
	add('tooltip', `open${d}`, { dark });
	add('dropdown-menu', `open${d}`, { dark });
	add('menubar', `default${d}`, { dark });
	add('command', `default${d}`, { dark });
}
for (const size of Object.keys(sheet.slots.button.size)) add('button', `size-${size}`, { size, text: size.startsWith('icon') ? '+' : 'Button' });
for (const size of ['sm', 'lg']) add('toggle', `size-${size}`, { size, text: 'Bold' });

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
}
*, *::before, *::after { animation: none !important; transition: none !important; }`;
const html = cases.map(c => markup[c.component](c)).join('\n');
const candidates = [...new Set([...html.matchAll(/class="([^"]*)"/g)].flatMap(m => m[1].split(/\s+/)).concat(['dark', 'bg-background', 'peer']))];
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
// (the element a state is forced on: the component's main slot)
const target = { label: 'label', 'radio-group': 'radio-group-item', slider: 'slider-thumb', tabs: 'tabs-trigger', toggle: 'toggle', select: 'select-trigger', 'dropdown-menu': 'dropdown-menu-item' };
for (const c of cases) {
	const align = c.block ? '' : 'display: flex; align-items: flex-start;';
	await page.setContent(`<!doctype html><html${c.dark ? ' class="dark"' : ''}><head><style>${css}</style></head>`
		+ `<body style="margin: 0"><div id="frame" class="bg-background" style="box-sizing: border-box; width: ${c.w}px; height: ${c.h}px; padding: 16px; ${align}">${markup[c.component](c)}</div></body></html>`);
	await page.evaluate(() => document.fonts.ready);
	await cdp.send('DOM.enable');
	await cdp.send('CSS.enable');
	const { root } = await cdp.send('DOM.getDocument');
	const force = async (selector, states) => {
		const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector });
		if (nodeId) await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: states.concat(states.includes('focus-visible') ? ['focus'] : []) });
	};
	if (c.states) await force(`[data-slot=${target[c.component] ?? c.component}]`, c.states);
	// (a menu's highlighted item: Radix focuses it)
	await force('[data-force-focus]', ['focus']);
	await page.locator('#frame').screenshot({ path: path.join(out, c.name + '.png') });
}
await browser.close();
const keys = ['name', 'component', 'w', 'h', 'block', 'variant', 'size', 'text', 'placeholder', 'checked', 'on', 'value', 'dark', 'states', 'attrs', 'peerDisabled', 'title', 'description', 'action', 'footer'];
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(cases.map(c => Object.fromEntries(keys.filter(k => c[k] !== undefined).map(k => [k, c[k]]))), null, '\t') + '\n');
console.log(`ref: ${cases.length} cases in ${path.relative(process.cwd(), out)}`);
