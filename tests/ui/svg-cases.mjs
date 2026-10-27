// Writes tests/ui/svg/: SVG documents of the subset helder.ui.Svg
// draws (icons with strokes, joins and caps; shapes; arcs and every path
// command; transforms; opacities; fill rules; colours; aspect ratios), each
// with the pixels Chromium draws it in (<case>.png, RGBA: the document drawn
// into a canvas at the case's size; cases.json: names and sizes), which
// UiTest compares with Svg.render's (npm test -- ui).
//   node tests/ui/svg-cases.mjs   (needs Playwright)
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'svg');
fs.mkdirSync(out, { recursive: true });

const svg = (body, attrs = 'viewBox="0 0 24 24"') => `<svg xmlns="http://www.w3.org/2000/svg" ${attrs}>${body}</svg>`;
const icon = (body, extra = '') => svg(body, `viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}`);

// [name, document, width, height]
const cases = [
	['icon-home', icon('<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>'), 48, 48],
	['icon-settings', icon('<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>'), 48, 48],
	['icon-small', icon('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', 'color="#2563eb"'), 24, 24],
	['icon-check-list', icon('<path d="M3 17l2 2 4-4"/><path d="M3 7l2 2 4-4"/><path d="M13 6h8"/><path d="M13 12h8"/><path d="M13 18h8"/>'), 40, 40],
	['shapes', svg('<rect x="1" y="1" width="10" height="8" fill="tomato"/><rect x="13" y="1" width="10" height="8" rx="3" fill="#3b82f6"/><circle cx="6" cy="16" r="5" fill="rgb(34, 197, 94)"/><ellipse cx="18" cy="16" rx="5" ry="3" fill="rebeccapurple" stroke="black" stroke-width="0.5"/>'), 48, 48],
	['rounded-rect-ry', svg('<rect x="2" y="2" width="20" height="14" rx="8" ry="3" fill="#f59e0b"/><rect x="4" y="18" width="16" height="4" rx="10" fill="#0ea5e9"/>'), 48, 48],
	['fill-rules', svg('<path d="M6 1 L9.5 11 L1 4.5 H11 L2.5 11 Z" fill="#ef4444"/><path fill-rule="evenodd" d="M18 1 L21.5 11 L13 4.5 H23 L14.5 11 Z" fill="#ef4444"/><path fill-rule="evenodd" d="M2 14h20v9H2z M6 16h12v5H6z" fill="#14b8a6"/>'), 48, 48],
	['arcs', svg('<path d="M2 12 A5 5 0 0 1 12 12" fill="none" stroke="black"/><path d="M13 6 a4 6 30 1 0 8 4" fill="none" stroke="#7c3aed" stroke-width="1.5"/><path d="M3 20 a6 3 0 0 0 9 0 a6 3 0 1 1 9 0" fill="none" stroke="#db2777"/><path d="M14 13 A3 3 0 1 1 14 13.01 Z" fill="#facc15"/>'), 64, 64],
	['curves', svg('<path d="M2 12 Q6 2 12 12 T22 12" fill="none" stroke="#2563eb" stroke-width="1.5"/><path d="M2 20 C4 14 8 14 10 20 S16 26 22 18" fill="none" stroke="#16a34a" stroke-width="1.5"/><path d="m2 4 c2-3 4 3 6 0 s4 3 6 0 q2-3 4 0 t4 0" fill="none" stroke="black"/>'), 64, 64],
	['path-syntax', svg('<path d="M2,2L10-5.5.5 8l3.5.5zM14 2h8v8h-8zm2 2v4h4V4z" fill="#0f766e" fill-rule="evenodd"/><path d="M2 14l4 8 4-8 4 8 4-8 4 8" fill="none" stroke="#9333ea" stroke-width="1.2e0"/>'), 48, 48],
	['transforms', svg('<g transform="translate(12 12) rotate(30)"><rect x="-6" y="-3" width="12" height="6" fill="#f97316"/></g><g transform="matrix(1 0 0.5 1 0 0)"><rect x="1" y="16" width="6" height="6" fill="#06b6d4"/></g><rect x="14" y="16" width="4" height="4" transform="scale(1.2) rotate(-15 16 18)" fill="#84cc16"/><g transform="skewY(20)"><circle cx="4" cy="3" r="2.5" fill="#e11d48"/></g>'), 64, 64],
	['opacity', svg('<g opacity="0.5"><circle cx="9" cy="10" r="6" fill="#ef4444"/><circle cx="15" cy="10" r="6" fill="#3b82f6"/></g><circle cx="7" cy="19" r="4" fill="#22c55e" fill-opacity="0.6"/><circle cx="12" cy="19" r="4" fill="#22c55e" stroke="#000" stroke-width="2" opacity="0.5"/><circle cx="18" cy="19" r="4" fill="none" stroke="#a855f7" stroke-width="2.5" stroke-opacity="0.4"/>'), 48, 48],
	['joins', svg('<polyline points="2,9 6,3 10,9 14,3" fill="none" stroke="#1e293b" stroke-width="2.5" stroke-linejoin="miter"/><polyline points="2,15 6,11 10,15 14,11" fill="none" stroke="#1e293b" stroke-width="2.5" stroke-linejoin="bevel"/><polyline points="2,21 6,17 10,21 14,17" fill="none" stroke="#1e293b" stroke-width="2.5" stroke-linejoin="round"/><polyline points="16,4 22,5 16,6" fill="none" stroke="#dc2626" stroke-width="1.5"/><polyline points="16,10 22,11 16,12" fill="none" stroke="#dc2626" stroke-width="1.5" stroke-miterlimit="20"/>'), 64, 64],
	['caps', svg('<line x1="4" y1="4" x2="20" y2="4" stroke="#334155" stroke-width="3"/><line x1="4" y1="10" x2="20" y2="10" stroke="#334155" stroke-width="3" stroke-linecap="square"/><line x1="4" y1="16" x2="20" y2="16" stroke="#334155" stroke-width="3" stroke-linecap="round"/><path d="M6 21 L18 23" stroke="#0369a1" stroke-width="2" stroke-linecap="round"/>'), 48, 48],
	['closed-stroke', svg('<rect x="3" y="3" width="8" height="8" fill="#fde68a" stroke="#92400e" stroke-width="2"/><polygon points="17,3 22,11 12,11" fill="none" stroke="#92400e" stroke-width="1.5"/><path d="M4 15 h7 v7 h-7 z" fill="none" stroke="#1d4ed8" stroke-width="2" stroke-linejoin="round"/><path d="M14 15 h7 v7 h-7" fill="none" stroke="#1d4ed8" stroke-width="2"/>'), 48, 48],
	['styles', svg('<g fill="#64748b" stroke-width="1"><rect x="2" y="2" width="8" height="8"/><rect x="14" y="2" width="8" height="8" style="fill: rgba(220, 38, 38, 0.7); stroke: navy"/></g><g style="fill:#0d9488"><circle cx="6" cy="17" r="4"/><circle cx="18" cy="17" r="4" fill="#f0f8"/></g><rect x="9" y="12" width="6" height="2" display="none" fill="red"/><defs><rect id="x" width="24" height="24" fill="red"/></defs>'), 48, 48],
	['current-color', svg('<g color="#be123c"><rect x="2" y="2" width="9" height="9" fill="currentColor"/><circle cx="17" cy="7" r="4" fill="none" stroke="currentColor" stroke-width="2"/></g><path d="M3 15 h18 v6 H3z" fill="currentColor"/>'), 48, 48],
	['aspect-meet', svg('<rect width="24" height="24" fill="#e2e8f0"/><circle cx="12" cy="12" r="10" fill="#0284c7"/>'), 64, 32],
	['aspect-min-max', svg('<rect width="24" height="24" fill="#e2e8f0"/><circle cx="12" cy="12" r="10" fill="#0284c7"/>', 'viewBox="0 0 24 24" preserveAspectRatio="xMinYMax meet"'), 32, 64],
	['aspect-slice', svg('<rect width="24" height="24" fill="#e2e8f0"/><circle cx="12" cy="12" r="10" fill="#0284c7"/>', 'viewBox="0 0 24 24" preserveAspectRatio="xMidYMid slice"'), 64, 32],
	['aspect-none', svg('<rect width="24" height="24" fill="#e2e8f0"/><circle cx="12" cy="12" r="10" fill="#0284c7"/>', 'viewBox="0 0 24 24" preserveAspectRatio="none"'), 64, 32],
	['linear-gradient', svg('<defs><linearGradient id="a"><stop offset="0" stop-color="#ef4444"/><stop offset="1" stop-color="#3b82f6"/></linearGradient><linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="20%" stop-color="gold"/><stop offset="50%" stop-color="#16a34a" stop-opacity="0.5"/><stop offset="80%" stop-color="navy"/></linearGradient></defs><rect x="1" y="1" width="22" height="10" rx="2" fill="url(#a)"/><circle cx="7" cy="18" r="5" fill="url(#b)"/><rect x="14" y="13" width="9" height="10" fill="none" stroke="url(#a)" stroke-width="2"/>'), 64, 64],
	['gradient-units', svg('<defs><linearGradient id="u" gradientUnits="userSpaceOnUse" x1="2" y1="0" x2="22" y2="0"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#f0f"/></linearGradient><linearGradient id="t" gradientTransform="rotate(45 0.5 0.5)" href="#u2"/><linearGradient id="u2"><stop offset="0" stop-color="#0ea5e9"/><stop offset="1" stop-color="#f97316"/></linearGradient></defs><rect x="2" y="2" width="20" height="6" fill="url(#u)"/><rect x="8" y="10" width="8" height="5" fill="url(#u)"/><rect x="2" y="16" width="20" height="7" fill="url(#t)"/>'), 64, 64],
	['radial-gradient', svg('<defs><radialGradient id="r"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#7c3aed"/></radialGradient><radialGradient id="f" cx="0.5" cy="0.5" r="0.5" fx="0.3" fy="0.3"><stop offset="0" stop-color="#fde047"/><stop offset="0.7" stop-color="#ea580c"/><stop offset="1" stop-color="#7f1d1d"/></radialGradient><radialGradient id="s" r="0.2" spreadMethod="reflect"><stop offset="0" stop-color="#22c55e"/><stop offset="1" stop-color="#064e3b"/></radialGradient></defs><circle cx="6" cy="6" r="5" fill="url(#r)"/><circle cx="18" cy="6" r="5" fill="url(#f)"/><rect x="2" y="13" width="20" height="10" fill="url(#s)"/>'), 64, 64],
	['dashes', svg('<line x1="2" y1="3" x2="22" y2="3" stroke="#0f172a" stroke-width="2" stroke-dasharray="4 2"/><line x1="2" y1="8" x2="22" y2="8" stroke="#0f172a" stroke-width="2" stroke-dasharray="3" stroke-dashoffset="1.5"/><line x1="2" y1="13" x2="22" y2="13" stroke="#be185d" stroke-width="2" stroke-linecap="round" stroke-dasharray="0 4"/><path d="M2 21 Q7 15 12 21 T22 21" fill="none" stroke="#2563eb" stroke-width="1.5" stroke-dasharray="5 2 1 2"/><polyline points="14,10 18,16 22,10" fill="none" stroke="#65a30d" stroke-width="1.5" stroke-dasharray="6 1"/>'), 64, 64],
	['use-symbol', svg('<defs><path id="tri" d="M0 0 L6 0 L3 5 Z"/><symbol id="star" viewBox="0 0 10 10"><path d="M5 0.5 6.3 3.6 9.6 3.9 7.1 6.1 7.9 9.4 5 7.7 2.1 9.4 2.9 6.1 0.4 3.9 3.7 3.6Z"/></symbol></defs><use href="#tri" x="2" y="2" fill="#dc2626"/><use href="#tri" x="10" y="2" fill="#2563eb" transform="rotate(10 13 4)"/><use xlink:href="#star" xmlns:xlink="http://www.w3.org/1999/xlink" x="2" y="10" width="12" height="12" fill="#ca8a04"/><use href="#star" x="15" y="12" width="8" height="8" fill="none" stroke="#ca8a04" stroke-width="0.8"/>'), 64, 64],
	['clip-path', svg('<defs><clipPath id="c"><circle cx="8" cy="8" r="6"/><rect x="12" y="2" width="6" height="6"/></clipPath><clipPath id="e" clip-rule="evenodd"><path d="M2 14h20v9H2z M6 16h12v5H6z"/></clipPath></defs><g clip-path="url(#c)"><rect x="0" y="0" width="24" height="12" fill="#0891b2"/><path d="M0 12 L24 0" stroke="#fff" stroke-width="2"/></g><rect x="0" y="12" width="24" height="12" fill="#c026d3" clip-path="url(#e)"/><rect x="18" y="2" width="4" height="4" transform="rotate(20 20 4)" clip-path="url(#c)" fill="black"/>'), 64, 64],
	['nested-svg', svg('<rect width="24" height="24" fill="#f1f5f9"/><svg x="2" y="2" width="10" height="10" viewBox="0 0 20 20"><circle cx="10" cy="10" r="12" fill="#0d9488"/></svg><svg x="13" y="13" width="9" height="9"><rect x="-3" y="-3" width="10" height="10" fill="#ea580c"/></svg>'), 48, 48],
	['no-viewbox', svg('<rect x="4" y="4" width="32" height="12" fill="#4338ca"/><circle cx="20" cy="30" r="8" fill="none" stroke="#4338ca" stroke-width="3"/>', 'width="40" height="40"'), 40, 40],
	['offset-viewbox', svg('<rect x="100" y="50" width="20" height="10" fill="#15803d"/><circle cx="110" cy="65" r="4" fill="#15803d"/>', 'viewBox="96 46 28 24"'), 56, 48],
];

function crc32(b) {
	let r = 0xffffffff;
	for (const x of b) {
		r ^= x;
		for (let k = 0; k < 8; k++) r = r & 1 ? 0xedb88320 ^ (r >>> 1) : r >>> 1;
	}
	return (r ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
	const h = Buffer.alloc(8);
	h.writeUInt32BE(data.length, 0);
	h.write(type, 4, 'latin1');
	const c = Buffer.alloc(4);
	c.writeUInt32BE(crc32(Buffer.concat([Buffer.from(type, 'latin1'), data])), 0);
	return Buffer.concat([h, data, c]);
}
// an RGBA8 PNG
function png(px, w, h) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 6;
	const raw = Buffer.alloc((4 * w + 1) * h);
	for (let y = 0; y < h; y++) px.copy(raw, y * (4 * w + 1) + 1, 4 * y * w, 4 * (y + 1) * w);
	return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const browser = await pw.chromium.launch();
const page = await browser.newPage();
const list = [];
for (const [name, doc, w, h] of cases) {
	fs.writeFileSync(path.join(out, name + '.svg'), doc + '\n');
	// (drawn at the case's size: the document's viewport w by h, as Svg.render(w, h) makes it)
	const open = doc.slice(0, doc.indexOf('>') + 1);
	const sized = open.replace(/ (width|height)="[^"]*"/g, '').replace('<svg ', `<svg width="${w}" height="${h}" `) + doc.slice(open.length);
	const px = await page.evaluate(async ({ doc, w, h }) => {
		const img = new Image();
		img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(doc);
		await img.decode();
		const c = document.createElement('canvas');
		c.width = w;
		c.height = h;
		const g = c.getContext('2d');
		g.drawImage(img, 0, 0, w, h);
		return Array.from(g.getImageData(0, 0, w, h).data);
	}, { doc: sized, w, h });
	fs.writeFileSync(path.join(out, name + '.png'), png(Buffer.from(px), w, h));
	list.push({ name, width: w, height: h });
}
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(list, null, '\t') + '\n');
console.log(`svg-cases.mjs: ${list.length} cases (chromium ${browser.version()})`);
await browser.close();
