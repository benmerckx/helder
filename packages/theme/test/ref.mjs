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
// Calendar is react-day-picker's markup with shadcn's classNames; sonner's toast
// its markup with its own stylesheet, laid out in place. A popup is compared
// in its box (crop: 8px around it), where hxmc places it by its trigger.
//   NODE_PATH=<dir>/node_modules node packages/theme/test/ref.mjs
// (with playwright, tailwindcss@4.3.3, tailwind-merge@3 and sonner@2.0.8 in <dir>)
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
	if (s == null) return [];
	if (typeof s === 'string') return [s];
	if (Array.isArray(s)) return s;
	if (s.extends) {
		const fixed = s.variant != null || s.size != null;
		return lists(sheet.slots[s.extends], fixed ? s.variant ?? 'default' : variant, fixed ? s.size ?? 'default' : size).concat(s.class ?? []);
	}
	// (states: classes under a state the widget sets, sheet's data-[side=right])
	const states = Object.entries(s.states ?? {}).map(([k, v]) => v.split(/\s+/).map(c => `${k}:${c}`).join(' '));
	return [].concat(s.base, s.variant?.[variant ?? 'default'] ?? [], s.size?.[size ?? 'default'] ?? [], states, s.class ?? []);
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
	x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>', minus: '<path d="M5 12h14"/>', search: '<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>', loader: '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>',
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
		? `<div class="flex items-center gap-3">${markup.checkbox({ attrs: { disabled: true, 'data-disabled': '' } }).replace('class="', 'class="peer ')}${el('label', 'label', esc(c.text))}</div>`
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
	'select-content': c => el('div', 'select-content', el('div', 'select-viewport', ['Apple', 'Banana', 'Blueberry', 'Grapes'].map((t, i) =>
		el('div', 'select-item', (i === 0 ? el('span', 'select-item-indicator', icon('check', 'size-4')) : '') + `<span>${t}</span>`,
			{ role: 'option', 'data-state': i === 0 ? 'checked' : 'unchecked', ...(i === 0 ? { 'data-highlighted': '', 'data-force-focus': '' } : {}) })).join('')),
		{ role: 'listbox', 'data-state': 'open', 'data-side': 'bottom' }),
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
	breadcrumb: c => `<nav aria-label="breadcrumb" data-slot="breadcrumb">${el('ol', 'breadcrumb-list', ['Home', 'Components'].map(t =>
		el('li', 'breadcrumb-item', el('a', 'breadcrumb-link', t, { href: '#' })) + el('li', 'breadcrumb-separator', icon(c.rtl ? 'chevron-left' : 'chevron-right'), { role: 'presentation', 'aria-hidden': 'true' })).join('')
		+ el('li', 'breadcrumb-item', el('span', 'breadcrumb-page', 'Breadcrumb', { role: 'link', 'aria-disabled': 'true', 'aria-current': 'page' })))}</nav>`,
	pagination: c => el('nav', 'pagination', el('ul', 'pagination-content',
		`<li data-slot="pagination-item">${el('a', 'pagination-previous', icon('chevron-left') + '<span class="hidden sm:block">Previous</span>', { href: '#', 'aria-label': 'Go to previous page' }).replace('data-slot="pagination-previous"', 'data-slot="pagination-link"')}</li>`
		+ [1, 2, 3].map(n => `<li data-slot="pagination-item">${el('a', 'pagination-link', n, { href: '#', ...(n === 2 ? { 'aria-current': 'page', 'data-active': 'true' } : {}) }, n === 2 ? 'outline' : 'ghost', 'icon')}</li>`).join('')
		+ `<li data-slot="pagination-item">${el('span', 'pagination-ellipsis', icon('more', 'size-4'), { 'aria-hidden': true })}</li>`
		+ `<li data-slot="pagination-item">${el('a', 'pagination-link', 10, { href: '#' }, 'ghost', 'icon')}</li>`
		+ `<li data-slot="pagination-item">${el('a', 'pagination-next', '<span class="hidden sm:block">Next</span>' + icon('chevron-right'), { href: '#', 'aria-label': 'Go to next page' }).replace('data-slot="pagination-next"', 'data-slot="pagination-link"')}</li>`),
		{ role: 'navigation', 'aria-label': 'pagination' }),
	dialog: c => el('div', 'dialog-overlay', '', { 'data-state': 'open' }) + el('div', 'dialog-content',
		el('div', 'dialog-header', el('h2', 'dialog-title', 'Edit profile') + el('p', 'dialog-description', "Make changes to your profile here. Click save when you're done."))
		+ el('div', 'dialog-footer', markup.button({ variant: 'outline', text: 'Cancel' }) + markup.button({ text: 'Save changes' }))
		+ el('button', 'dialog-close', icon('x'), { type: 'button' }),
		{ role: 'dialog', 'data-state': 'open' }),
	sheet: c => el('div', 'sheet-overlay', '', { 'data-state': 'open' }) + el('div', 'sheet-content',
		el('div', 'sheet-header', el('h2', 'sheet-title', 'Edit profile') + el('p', 'sheet-description', "Make changes to your profile here. Click save when you're done."))
		+ el('div', 'sheet-footer', markup.button({ text: 'Save changes' }) + markup.button({ variant: 'outline', text: 'Close' }))
		+ `<button type="button" class="${twMerge(sheet.slots['sheet-close'])}">${icon('x', 'size-4')}</button>`,
		{ role: 'dialog', 'data-state': 'open', 'data-side': 'right' }),
	popover: c => el('div', 'popover-content', el('div', 'popover-header', el('div', 'popover-title', 'Dimensions') + el('div', 'popover-description', 'Set the dimensions for the layer.')), { 'data-state': 'open', 'data-side': 'bottom' }),
	'hover-card': c => el('div', 'hover-card-content', '<p class="text-sm">The React Framework, created and maintained by @vercel.</p>', { 'data-state': 'open', 'data-side': 'bottom' }),
	tooltip: c => el('div', 'tooltip-content', 'Add to library', { 'data-state': 'delayed-open', 'data-side': 'top' }),
	'dropdown-menu': c => menu('dropdown-menu', c),
	'context-menu': c => menu('context-menu', c),
	menubar: c => el('div', 'menubar', ['File', 'Edit', 'View'].map(t => el('button', 'menubar-trigger', t, { type: 'button', role: 'menuitem', 'data-state': 'closed' })).join(''), { role: 'menubar' }),
	'menubar-content': c => menu('menubar', c, [['New Tab', 'Ctrl+T'], ['New Window', 'Ctrl+N'], null, ['Share'], ['Print', 'Ctrl+P']]),
	combobox: c => `<div data-slot="popover-content" data-state="open" data-side="bottom" class="${twMerge(lists(sheet.slots['popover-content']).concat('w-[200px] p-0'))}">`
		+ el('div', 'command', el('div', 'command-list', el('div', 'command-group', ['Next.js', 'SvelteKit', 'Nuxt.js', 'Remix', 'Astro'].map((t, i) =>
			el('div', 'command-item', t, { role: 'option', 'data-selected': i === 0 ? 'true' : 'false', 'data-disabled': 'false' })).join(''), { role: 'presentation' }), { role: 'listbox' })) + '</div>',
	command: c => el('div', 'command', el('div', 'command-input-wrapper', icon('search', 'size-4 shrink-0 opacity-50')
		+ `<input data-slot="command-input" class="${classes('command-input')}" placeholder="Type a command or search...">`)
		+ el('div', 'command-list', [['Suggestions', [['Calendar'], ['Search Emoji'], ['Calculator', null, true]]], ['Settings', [['Profile', 'Ctrl+P'], ['Billing', 'Ctrl+B'], ['Settings', 'Ctrl+S']]]].map(([h, items], g) =>
			(g > 0 ? el('div', 'command-separator', '', { role: 'separator' }) : '') + el('div', 'command-group', `<div cmdk-group-heading="" aria-hidden="true">${h}</div><div cmdk-group-items="" role="group">`
				+ items.map(([t, k, off], i) => el('div', 'command-item', esc(t) + (k ? el('span', 'command-shortcut', k) : ''), { role: 'option', 'data-selected': g === 0 && i === 0 ? 'true' : 'false', 'data-disabled': off ? 'true' : 'false' })).join('') + '</div>', { role: 'presentation' })).join(''), { role: 'listbox' }))
		.replace('class="', 'class="rounded-lg border shadow-md md:min-w-[450px] '),
	'alert-dialog': c => el('div', 'alert-dialog-overlay', '', { 'data-state': 'open' }) + el('div', 'alert-dialog-content',
		el('div', 'alert-dialog-header', el('h2', 'alert-dialog-title', 'Are you absolutely sure?') + el('p', 'alert-dialog-description', 'This action cannot be undone. This will permanently delete your account and remove your data from our servers.'))
		+ el('div', 'alert-dialog-footer', markup.button({ variant: 'outline', text: 'Cancel' }) + markup.button({ text: 'Continue' })),
		{ role: 'alertdialog', 'data-state': 'open', 'data-size': 'default' }),
	'input-otp': c => el('div', 'input-otp', [[0, 1, 2], [3, 4, 5]].map((g, k) => (k > 0 ? `<div data-slot="input-otp-separator" role="separator">${icon('minus')}</div>` : '')
		+ el('div', 'input-otp-group', g.map(i => el('div', 'input-otp-slot', (i < 2 ? '12'[i] : '') + (i === 2 ? `<div class="pointer-events-none absolute inset-0 flex items-center justify-center"><div class="${twMerge(sheet.slots['input-otp-caret'])}"></div></div>` : ''),
			{ 'data-active': i === 2 ? 'true' : 'false' })).join(''))).join('')),
	drawer: c => el('div', 'drawer-overlay', '', { 'data-state': 'open' }) + el('div', 'drawer-content',
		el('div', 'drawer-handle') + el('div', 'drawer-header', el('h2', 'drawer-title', 'Move Goal') + el('p', 'drawer-description', 'Set your daily activity goal.'))
		+ el('div', 'drawer-footer', markup.button({ text: 'Submit' }) + markup.button({ variant: 'outline', text: 'Cancel' })),
		{ role: 'dialog', 'data-state': 'open', 'data-vaul-drawer-direction': 'bottom' }),
	'dropdown-menu-items': c => el('div', 'dropdown-menu-content', el('div', 'dropdown-menu-label', 'Appearance')
		+ el('div', 'dropdown-menu-checkbox-item', `<span data-slot="dropdown-menu-item-indicator" class="${twMerge(sheet.slots['dropdown-menu-item-indicator'])}">${icon('check', 'size-4')}</span>Status Bar`, { role: 'menuitemcheckbox', 'aria-checked': 'true', 'data-state': 'checked', 'data-highlighted': '', 'data-force-focus': '' })
		+ el('div', 'dropdown-menu-checkbox-item', `<span data-slot="dropdown-menu-item-indicator" class="${twMerge(sheet.slots['dropdown-menu-item-indicator'])}"></span>Panel`, { role: 'menuitemcheckbox', 'aria-checked': 'false', 'data-state': 'unchecked' })
		+ el('div', 'dropdown-menu-separator', '', { role: 'separator' })
		+ el('div', 'dropdown-menu-sub-trigger', 'More' + icon('chevron-right', 'ml-auto size-4'), { role: 'menuitem', 'data-state': 'closed' }),
		{ role: 'menu', 'data-state': 'open', 'data-side': 'bottom' }),
	avatar: c => el('span', 'avatar', el('span', 'avatar-fallback', 'CN'), { 'data-size': 'default' }),
	kbd: c => el('kbd', 'kbd', 'Ctrl'),
	spinner: c => icon('loader', classes('spinner')).replace('<svg ', '<svg data-slot="spinner" role="status" aria-label="Loading" '),
	resizable: c => el('div', 'resizable-panel-group', el('div', 'resizable-panel', '<div class="flex h-full items-center justify-center p-6"><span class="font-semibold">One</span></div>', { style: 'flex: 0 0 150px; overflow: hidden;' })
		+ el('div', 'resizable-handle', '', { role: 'separator', 'aria-orientation': 'vertical', 'data-panel-group-direction': 'horizontal' })
		+ el('div', 'resizable-panel', '<div class="flex h-full items-center justify-center p-6"><span class="font-semibold">Two</span></div>', { style: 'flex: 1 1 0; overflow: hidden;' }),
		{ 'aria-orientation': 'horizontal', 'data-panel-group-direction': 'horizontal' }).replace('class="', 'class="rounded-lg border '),
	calendar: c => calendar(c),
	toast: c => `<section aria-label="Notifications alt+T" tabindex="-1"><ol data-sonner-toaster="true" data-sonner-theme="${c.dark ? 'dark' : 'light'}" class="toaster group" dir="${c.rtl ? 'rtl' : 'ltr'}" data-y-position="bottom" data-x-position="right" style="--normal-bg: var(--popover); --normal-text: var(--popover-foreground); --normal-border: var(--border); --border-radius: var(--radius); --width: 356px; --gap: 14px;">`
		+ `<li data-sonner-toast="" data-styled="true" data-mounted="true" data-visible="true" data-front="true" data-y-position="bottom" data-x-position="right" data-type="default">`
		+ `<button aria-label="Close toast" data-close-button="true">${icon('x').replace('width="24" height="24"', 'width="12" height="12"').replace('stroke-width="2"', 'stroke-width="1.5"')}</button>`
		+ `<div data-content=""><div data-title="">${esc(c.text)}</div></div><button data-button="true" data-action="true">${esc(c.action)}</button></li></ol></section>`,
};

// a menu's content, as hxmc's MenuItems make it: items with shortcuts, a separator, a destructive and a disabled one (the first focused)
function menu(kind, c, items = [['Profile', 'Ctrl+P'], ['Billing', 'Ctrl+B'], null, ['Delete', null, 'destructive'], ['Disabled', null, 'default', true]]) {
	return el('div', `${kind}-content`, items.map((it, i) => it == null ? el('div', `${kind}-separator`, '', { role: 'separator' })
		: el('div', `${kind}-item`, esc(it[0]) + (it[1] ? el('span', `${kind}-shortcut`, it[1]) : ''),
			{ role: 'menuitem', 'data-variant': it[2] ?? 'default', ...(it[3] ? { 'data-disabled': '' } : {}), ...(i === 0 ? { 'data-highlighted': '', 'data-force-focus': '' } : {}) }, it[2] ?? 'default')).join(''),
		{ role: 'menu', 'data-state': 'open', 'data-side': 'bottom', dir: c.rtl ? 'rtl' : 'ltr' });
}

// react-day-picker's markup with shadcn's classNames (calendar-<part>):
// October 2026 from Sunday, six weeks, the 12th selected, the 17th today
function calendar(c) {
	const cls = (part, extra = '') => twMerge(lists(sheet.slots['calendar-' + part]).concat(extra));
	const days = [];
	for (let i = 0; i < 42; i++) {
		const date = new Date(2026, 9, 1 - 4 + i), d = date.getDate(), outside = date.getMonth() !== 9;
		const selected = !outside && d === 12, today = !outside && d === 17;
		const td = cls('day', [outside ? lists(sheet.slots['calendar-outside']) : [], today ? lists(sheet.slots['calendar-today']) : []].flat().join(' '));
		days.push(`<td class="${td}" role="gridcell"${selected ? ' data-selected="true" aria-selected="true"' : ''}${today ? ' data-today="true"' : ''}${outside ? ' data-outside="true"' : ''}>`
			+ `<button data-slot="button" class="${cls('day-button')}" type="button" data-day="${date.toLocaleDateString('en-US')}" data-selected-single="${selected}" tabindex="${selected ? 0 : -1}">${d}</button></td>`);
	}
	const weeks = [0, 1, 2, 3, 4, 5].map(w => `<tr class="${cls('week')}">${days.slice(w * 7, w * 7 + 7).join('')}</tr>`).join('');
	const button = (part, ic, label) => `<button class="${cls(part)}" aria-label="${label}" type="button">${icon(ic, 'size-4')}</button>`;
	return `<div data-slot="calendar" class="${cls('root', twMerge(sheet.slots.calendar))}" dir="${c.rtl ? 'rtl' : 'ltr'}"><div class="${cls('months')}">`
		+ `<nav aria-label="Navigation bar" class="${cls('nav')}">${button('button-previous', 'chevron-left', 'Go to the Previous Month')}${button('button-next', 'chevron-right', 'Go to the Next Month')}</nav>`
		+ `<div class="${cls('month')}"><div class="${cls('month-caption')}"><span class="${cls('caption-label')}" role="status" aria-live="polite">October 2026</span></div>`
		+ `<table role="grid" class="${cls('month-grid')}"><thead aria-hidden="true"><tr class="${cls('weekdays')}">${['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map(d => `<th scope="col" class="${cls('weekday')}">${d}</th>`).join('')}</tr></thead>`
		+ `<tbody>${weeks}</tbody></table></div></div></div>`;
}

// the frame each component is drawn in (padding 16 around it); block: as wide as the frame
const frames = {
	button: { w: 160, h: 68 }, badge: { w: 120, h: 54 }, input: { w: 280, h: 68, block: true }, checkbox: { w: 48, h: 48 },
	switch: { w: 64, h: 51 }, label: { w: 200, h: 48 }, card: { w: 360, h: 248, block: true }, textarea: { w: 280, h: 96, block: true },
	'radio-group': { w: 180, h: 76 }, slider: { w: 240, h: 48, block: true }, tabs: { w: 320, h: 112 }, progress: { w: 240, h: 40, block: true },
	separator: { w: 240, h: 92, block: true }, skeleton: { w: 300, h: 80 }, toggle: { w: 120, h: 68 }, 'toggle-group': { w: 280, h: 68 },
	alert: { w: 400, h: 116, block: true }, select: { w: 220, h: 68 }, 'select-content': { w: 200, h: 200 }, table: { w: 360, h: 200, block: true },
	accordion: { w: 400, h: 200, block: true }, breadcrumb: { w: 360, h: 52 }, pagination: { w: 420, h: 68, block: true }, dialog: { w: 800, h: 600 },
	popover: { w: 320, h: 120 }, tooltip: { w: 160, h: 60 }, 'dropdown-menu': { w: 240, h: 240 }, menubar: { w: 240, h: 68 },
	// (a popup: drawn in a larger frame, compared in its box, 8px around it for its shadow; refCrop: the element, where it is not the slot hxmc crops)
	command: { w: 482, h: 300 }, combobox: { w: 320, h: 300, crop: 'command-list', refCrop: 'popover-content' }, 'alert-dialog': { w: 800, h: 600 }, drawer: { w: 800, h: 600 }, 'input-otp': { w: 320, h: 68 },
	'dropdown-menu-items': { w: 320, h: 300, crop: 'dropdown-menu-content' }, 'context-menu': { w: 320, h: 300, crop: 'context-menu-content' },
	'menubar-content': { w: 320, h: 300, crop: 'menubar-content' }, 'hover-card': { w: 320, h: 200, crop: 'hover-card-content' },
	sheet: { w: 800, h: 600 }, avatar: { w: 64, h: 64 }, kbd: { w: 80, h: 52 }, spinner: { w: 48, h: 48 }, resizable: { w: 400, h: 192, block: true },
	calendar: { w: 300, h: 340 }, toast: { w: 420, h: 140, crop: 'toast', refCrop: '[data-sonner-toast]' },
};
for (const k of ['select-content', 'dropdown-menu', 'popover', 'tooltip']) Object.assign(frames[k], { w: 360, h: 300, crop: k === 'dropdown-menu' ? 'dropdown-menu-content' : k === 'popover' ? 'popover-content' : k === 'tooltip' ? 'tooltip-content' : k });

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
	add('combobox', `open${d}`, { dark });
	add('alert-dialog', `open${d}`, { dark });
	add('drawer', `open${d}`, { dark });
	add('input-otp', `active${d}`, { dark });
	add('dropdown-menu-items', `open${d}`, { dark });
	add('context-menu', `open${d}`, { dark });
	add('menubar-content', `open${d}`, { dark });
	add('hover-card', `open${d}`, { dark });
	add('sheet', `open${d}`, { dark });
	add('avatar', `fallback${d}`, { dark });
	add('kbd', `default${d}`, { dark });
	add('spinner', `default${d}`, { dark });
	add('resizable', `horizontal${d}`, { dark });
	add('calendar', `default${d}`, { dark });
	add('toast', `default${d}`, { dark, text: 'Event has been created', action: 'Undo' });
}
// right to left (dir="rtl" on the page; hxmc: the frame's direction)
add('card', 'full-rtl', { title: 'Card Title', description: 'Card Description', action: 'Card Action', text: 'Card Content', footer: 'Card Footer', rtl: true });
add('alert', 'default-rtl', { variant: 'default', title: 'Heads up!', text: 'You can add components to your app using the cli.', rtl: true });
add('input', 'value-rtl', { text: 'hello@example.com', rtl: true });
add('breadcrumb', 'default-rtl', { rtl: true });
add('pagination', 'default-rtl', { rtl: true });
add('dropdown-menu', 'open-rtl', { rtl: true });
add('calendar', 'default-rtl', { rtl: true });
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

// sonner's own stylesheet, its toast laid out in place (not stacked at the window's corner), in Inter
const sonner = fs.readFileSync(require.resolve('sonner/dist/styles.css'), 'utf8')
	+ '[data-sonner-toaster] { position: static !important; font-family: Inter, sans-serif !important; } [data-sonner-toast] { position: relative !important; opacity: 1 !important; transform: none !important; }';

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 800, height: 600 }, deviceScaleFactor: 1 });
const cdp = await page.context().newCDPSession(page);
// (the element a state is forced on: the component's main slot)
const target = { label: 'label', 'radio-group': 'radio-group-item', slider: 'slider-thumb', tabs: 'tabs-trigger', toggle: 'toggle', select: 'select-trigger', 'dropdown-menu': 'dropdown-menu-item' };
for (const c of cases) {
	const align = c.block ? '' : 'display: flex; align-items: flex-start;';
	await page.setContent(`<!doctype html><html${c.dark ? ' class="dark"' : ''}${c.rtl ? ' dir="rtl"' : ''}><head><style>${css}${c.component === 'toast' ? sonner : ''}</style></head>`
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
	if (c.crop) {
		// (a popup in its box, 8px around it)
		const sel = c.refCrop ? (c.refCrop.startsWith('[') ? c.refCrop : `[data-slot=${c.refCrop}]`) : `[data-slot=${c.crop}]`;
		const b = await page.locator(sel).first().boundingBox();
		const clip = { x: Math.round(b.x) - 8, y: Math.round(b.y) - 8, width: Math.round(b.width) + 16, height: Math.round(b.height) + 16 };
		Object.assign(c, { fw: c.w, fh: c.h, w: clip.width, h: clip.height });
		await page.screenshot({ path: path.join(out, c.name + '.png'), clip });
	} else await page.locator('#frame').screenshot({ path: path.join(out, c.name + '.png') });
}
await browser.close();
const keys = ['name', 'component', 'w', 'h', 'block', 'variant', 'size', 'text', 'placeholder', 'checked', 'on', 'value', 'dark', 'states', 'attrs', 'peerDisabled', 'title', 'description', 'action', 'footer', 'rtl', 'crop', 'fw', 'fh'];
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(cases.map(c => Object.fromEntries(keys.filter(k => c[k] !== undefined).map(k => [k, c[k]]))), null, '\t') + '\n');
console.log(`ref: ${cases.length} cases in ${path.relative(process.cwd(), out)}`);
