// helder studio in the browser (bun run test studio-web): the page that
// apps/studio/web/build.mjs writes, in headless Chromium on WebGPU
// (SwiftShader), driven by real input (Playwright's mouse, keyboard and
// touches, CDP's two-finger touches), its own module's canvas read back
// (host.gfx.readPixels: what the studio drew, the preview's frames
// composited) against goldens:
//
// - desktop (1180 x 740): the welcome's Todo opened (an example bundled
//   with the page: OPFS, the preview host started in its worker), all four
//   screens shown, a screen zoomed into, its title clicked and selected
//   (Ui.getTree through the worker), its colour changed in the inspector:
//   a live literal patched in the preview host, the next frames show it
//   (frames counted, the title's pixels red), the file saved in OPFS; a
//   structural edit (a padding added) built by the compiler's worker
//   (helder.compiler.web: the site built with it, the lane's) and the
//   preview swapped in with its state, the title's box grown in the new
//   build's tree (a site without that worker: saved and said);
// - agents: run.snap of a story's screen (the preview's frame as a PNG);
//   a design file opened from an #import= link, the studio's tools
//   registered with WebMCP (a stand-in document.modelContext) and called:
//   read, patched (undone from the header), its tree, its frame's PNG
//   (drawn into a render target); a deflated (z.) link; a Haxe app
//   (examples/signup) from a link, built at its open;
// - phone (390 x 844, touch): the same project in the compact layout, a
//   screen tapped, the inspector a bottom sheet, the title tapped, its
//   colour patched, a pinch zooming the canvas, the screens' drawer;
// - 50 screens (tests/story/host/host.mjs project): opened, the time to
//   every screen shown, the memory (the studio's module, the preview's,
//   the page's JavaScript), the frames each screen drew.
//
//   node tests/studio-web/check.mjs <site> <out> [--bless]
//
// Goldens (tests/studio-web/*.png): the overview and the zoomed state at
// both widths; BLESS writes them. The numbers go to <out>/results.md, the
// page's screenshots to <out>.
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try {
	pw = require('playwright');
} catch {
	pw = require(path.join(process.execPath, '../../lib/node_modules/playwright'));
}
const here = path.dirname(fileURLToPath(import.meta.url));
const [site, out] = process.argv.slice(2);
const BLESS = process.argv.includes('--bless') || !!process.env.BLESS;
await mkdir(out, { recursive: true });
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.html': 'text/html', '.ttf': 'font/ttf', '.png': 'image/png' };
const server = createServer(async (req, res) => {
	let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	if (p === '/') p = '/index.html';
	const file = p.startsWith('/goldens/') ? path.join(here, p.slice(9)) : path.join(site, p);
	try {
		const b = await readFile(file);
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/`;
const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader', '--enable-precise-memory-info'] });
console.log(`studio-web: chromium ${browser.version()}`);

let failures = 0, checks = 0;
const numbers = [];
function check(ok, what) {
	checks++;
	if (ok) console.log(`studio-web: ok: ${what}`);
	else {
		failures++;
		console.log(`studio-web: FAIL: ${what}`);
	}
}

async function page(viewport, touch) {
	const ctx = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch, deviceScaleFactor: 1 });
	const pg = await ctx.newPage();
	pg.on('pageerror', (e) => console.log('studio-web: page error: ' + e.message));
	pg.on('console', (m) => /error|exit|stderr/i.test(m.text()) && console.log('studio-web: console: ' + m.text().slice(0, 400)));
	await pg.goto(base);
	await ready(pg);
	return pg;
}

const ready = (pg) => pg.waitForFunction(() => window.studioWeb?.ready || window.studioWeb?.error, null, { timeout: 60000 });
const events = (pg) => pg.evaluate(() => window.studioWeb.events);
async function event(pg, name, pred = () => true, timeout = 30000) {
	const t0 = Date.now();
	while (Date.now() - t0 < timeout) {
		const e = (await events(pg)).filter((x) => x.event === name).find(pred);
		if (e) return e;
		await pg.waitForTimeout(50);
	}
	return null;
}
const lastFrame = async (pg) => (await events(pg)).reduce((n, e) => Math.max(n, e.frame ?? 0), 0);

// a control of the studio by its accessible name (its ARIA mirror in the canvas), activated as a screen reader would
async function press(pg, label) {
	return pg.evaluate((label) => {
		const e = [...document.querySelectorAll('#studio [role=button]')].find((x) => x.getAttribute('aria-label') === label);
		if (!e) return false;
		e.click();
		return true;
	}, label);
}

async function openExample(pg, label) {
	check(await press(pg, label), `the welcome lists ${label}`);
	await pg.waitForURL(/project=/, { timeout: 30000 });
	await ready(pg);
	return event(pg, 'all-shown', () => true, 60000);
}

// the studio's canvas as it drew it: against a golden (or written as it, blessing)
async function golden(pg, name) {
	const r = await pg.evaluate(async ({ name, bless }) => {
		const h = window.studioWeb.host;
		const p = h.gfx.readPixels();
		h.os.redraw();
		const px = await p;
		if (bless) {
			const c = new OffscreenCanvas(px.width, px.height);
			c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(px.data), px.width, px.height), 0, 0);
			const b = new Uint8Array(await (await c.convertToBlob({ type: 'image/png' })).arrayBuffer());
			let s = '';
			for (const x of b) s += String.fromCharCode(x);
			return { png: btoa(s) };
		}
		const res = await fetch('/goldens/' + name + '.png');
		if (!res.ok) return { text: 'no golden ' + name + '.png (BLESS=1 writes it)' };
		const img = await createImageBitmap(await res.blob(), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
		const c = new OffscreenCanvas(img.width, img.height).getContext('2d');
		c.drawImage(img, 0, 0);
		const g = c.getImageData(0, 0, img.width, img.height).data;
		if (img.width !== px.width || img.height !== px.height) return { text: `${px.width}x${px.height}, the golden ${img.width}x${img.height}` };
		let off = 0, most = 0;
		for (let i = 0; i < g.length; i += 4) {
			const d = Math.max(Math.abs(g[i] - px.data[i]), Math.abs(g[i + 1] - px.data[i + 1]), Math.abs(g[i + 2] - px.data[i + 2]));
			if (d > 24) off++;
			most = Math.max(most, d);
		}
		const n = px.width * px.height;
		return { ok: off <= n * 0.005, text: `${off} of ${n} pixels off by more than 24 (at most ${most})` };
	}, { name, bless: BLESS });
	await pg.screenshot({ path: path.join(out, name + '.png') });
	if (r.png) {
		await writeFile(path.join(here, name + '.png'), Buffer.from(r.png, 'base64'));
		console.log(`studio-web: ${name}.png blessed`);
	} else check(r.ok, `${name}: ${r.text}`);
}

// a PNG's size (base64)
function png(b64) {
	const b = Buffer.from(b64, 'base64');
	return b.toString('latin1', 1, 4) === 'PNG' ? { width: b.readUInt32BE(16), height: b.readUInt32BE(20) } : null;
}

// a pixel of the studio's canvas
async function pixel(pg, x, y) {
	return pg.evaluate(async ([x, y]) => {
		const h = window.studioWeb.host;
		const p = h.gfx.readPixels();
		h.os.redraw();
		const d = await p;
		const i = (y * d.width + x) * 4;
		return [d.data[i], d.data[i + 1], d.data[i + 2]];
	}, [x, y]);
}
const red = (c) => c[0] > 200 && c[1] < 110 && c[2] < 110;

// the colour typed into the inspector's colour field (at x, y): a live literal patched, its frames
async function recolour(pg, x, y, tap) {
	const before = await lastFrame(pg);
	if (tap) await pg.touchscreen.tap(x, y);
	else await pg.mouse.click(x, y);
	await pg.waitForTimeout(300);
	await pg.keyboard.press('Control+a');
	await pg.keyboard.type('#ef4444');
	await pg.keyboard.press('Enter');
	const patched = await event(pg, 'patched', (e) => e.frame >= before);
	const shown = await event(pg, 'patch-shown', (e) => e.frame >= before);
	check(patched && patched.patches.length === 1 && patched.patches[0].source === '"#ef4444"', 'the colour a live literal patch, nothing built: ' + JSON.stringify(patched?.patches));
	check(shown && shown.frames <= 3, `the patch shown in the preview's next frames: ${shown?.ms} ms, ${shown?.frames} studio frame(s)`);
	const saved = await pg.evaluate(async () => {
		await window.studioWeb.saved?.();
		const d = await (await (await navigator.storage.getDirectory()).getDirectoryHandle('projects')).getDirectoryHandle(window.studioWeb.project);
		return (await (await d.getFileHandle('Todo.hx')).getFile()).text();
	});
	check(saved.includes('color="#ef4444"'), 'Todo.hx saved in OPFS with the colour');
	return shown;
}

// ---- desktop
{
	const pg = await page({ width: 1180, height: 740 }, false);
	await pg.screenshot({ path: path.join(out, 'desktop-welcome.png') });
	const shown = await openExample(pg, 'Todo');
	const by = await pg.evaluate(() => window.studioWeb.framesByScreen);
	check(shown && shown.screens === 4 && Object.keys(by).length === 4, `all 4 screens shown (${shown?.ms} ms after opening, frames by screen ${JSON.stringify(by)})`);
	const started = await pg.evaluate(() => window.studioWeb.started);
	numbers.push(['todo (4 screens)', 'desktop', started, shown]);
	await pg.waitForTimeout(400);
	await golden(pg, 'desktop-overview');
	// (the sidebar's frame row: selected, the camera flown to it)
	await pg.mouse.click(94, 277);
	await pg.waitForTimeout(1600);
	await golden(pg, 'desktop-zoomed');
	// (a double click: the frame entered, its title selected)
	await pg.mouse.dblclick(420, 122);
	const sel = await event(pg, 'selected');
	check(sel && sel.tag === 'text' && sel.screen === 'Todo/Three items' && sel.rect.join() === '24,24,432,35', 'the title selected: ' + JSON.stringify(sel && [sel.screen, sel.tag, sel.rect]));
	await pg.waitForTimeout(400);
	await pg.screenshot({ path: path.join(out, 'desktop-selected.png') });
	const p = await recolour(pg, 1076, 327, false);
	numbers.push(['desktop patch', p]);
	check(red(await pixel(pg, 380, 124)), 'the title red in the studio\'s canvas (the preview\'s frame, composited)');
	await pg.screenshot({ path: path.join(out, 'desktop-colored.png') });
	// (an agent's run.snap of a story's screen: the preview's frame as a PNG, made by the page)
	const shot = await pg.evaluate(() => window.studioWeb.call('run.snap', { screen: 'Todo/Three items' }));
	const img = shot.content.find((c) => c.type === 'image');
	check(img && png(img.data)?.width >= 480, `run.snap of a story's screen: a PNG ${img && JSON.stringify(png(img.data))} ${shot.content.at(-1).text}`);
	// a structural edit: the compiler's worker builds it, or the studio says it cannot yet
	await pg.waitForFunction(() => window.studioWeb.compiler !== undefined, null, { timeout: 60000 }).catch(() => {});
	const compiler = await pg.evaluate(() => !!window.studioWeb.compiler);
	const before = await lastFrame(pg);
	await pg.mouse.click(1076, 173);
	await pg.waitForTimeout(200);
	await pg.keyboard.type('20');
	await pg.keyboard.press('Enter');
	const built = await event(pg, 'built', (e) => e.frame >= before, compiler ? 180000 : 10000);
	if (compiler) {
		check(built && built.ok, `a padding added: built by the compiler's worker in ${built?.ms} ms (${JSON.stringify(built)})`);
		// (the new build's preview: the title's box grown by its padding, read from its tree again)
		const grown = await event(pg, 'selection', (e) => e.frame > built.frame && e.rect && e.rect[3] > 35, 30000);
		check(grown, `the screens reloaded from the new build, the title's box ${JSON.stringify(grown?.rect)}`);
		// undone: the attribute removed, a warm build
		const at = await lastFrame(pg);
		check(await press(pg, 'Undo'), 'the padding undone (the header\'s Undo)');
		const again = await event(pg, 'built', (e) => e.frame > at, 120000);
		check(again && again.ok, `the undo built warm in ${again?.ms} ms`);
		const back = await event(pg, 'selection', (e) => e.frame > again.frame && e.rect && e.rect[3] === 35, 30000);
		await pg.screenshot({ path: path.join(out, 'desktop-undone.png') });
		check(back, `the title's box back to 35 high ${JSON.stringify(back?.rect)}` + (back ? '' : ' ' + JSON.stringify((await events(pg)).filter((e) => e.frame >= at).map((e) => [e.event, e.frame, e.rect, e.ok])) + JSON.stringify(await pg.evaluate(() => [window.studioWeb.frames, window.studioWeb.logs.slice(-12)]))));
		numbers.push(['structural', built, grown, await pg.evaluate(() => window.studioWeb.compilerInit), again]);
		await pg.screenshot({ path: path.join(out, 'desktop-built.png') });
	} else {
		check(built && !built.ok, 'a padding added: saved, not built (no compiler worker on this page yet)');
		console.log('studio-web: structural edits: skipped, the page has no compiler worker (helder.compiler.web)');
	}
	await pg.context().close();
}

// ---- agents: the studio's tools through WebMCP (a stand-in document.modelContext;
// a browser with WebMCP is given the same table), on a design file opened
// from an #import= link (JSON as base64url), then one deflated (z.)
{
	const ctx = await browser.newContext({ viewport: { width: 1180, height: 740 } });
	await ctx.addInitScript(() => {
		const tools = new Map();
		document.modelContext = { registerTool: (t) => void tools.set(t.name, t), tools };
	});
	const pg = await ctx.newPage();
	const design = '<Design>\n\t<Frame name="Card" width={200} height={120} background="#ffffff" padding="16">\n\t\t<text color="#dc2626">Hello</text>\n\t</Frame>\n</Design>\n';
	const data = Buffer.from(JSON.stringify({ name: 'agent', files: { 'app.helder': design } })).toString('base64url');
	await pg.goto(base + '#import=' + data);
	await pg.waitForURL(/project=agent/, { timeout: 30000 });
	await ready(pg);
	check(await event(pg, 'designs-shown'), 'an #import= link opened as a project of OPFS, its frame shown');
	const names = await pg.waitForFunction(() => document.modelContext.tools.size >= 8 && [...document.modelContext.tools.keys()], null, { timeout: 10000 }).then((h) => h.jsonValue(), () => []);
	check(names.length === 8 && ['project.read', 'project.patch', 'build.check', 'run.snap', 'run.tree', 'project.create', 'project.list', 'project.open'].every((n) => names.includes(n)), 'WebMCP: the tools registered: ' + names.join(', '));
	const run = (name, args) => pg.evaluate(([n, a]) => document.modelContext.tools.get(n).execute(a), [name, args]);
	const read = await run('project.read', { path: 'app.helder' });
	check(read.content[0].text === design, 'project.read: the file');
	const patched = await run('project.patch', { path: 'app.helder', edits: [{ old: 'Hello', new: 'Hi there' }] });
	check(!patched.isError, 'project.patch: ' + patched.content[0].text.replace(/\s+/g, ' '));
	const tree = await run('run.tree', { screen: 'app.helder#Card' });
	check(tree.content[0].text.includes('"Hi there"'), 'run.tree: the patched text in the frame\'s nodes');
	const snap = await run('run.snap', { screen: 'app.helder#Card' });
	const img = snap.content.find((c) => c.type === 'image');
	const size = img && png(img.data);
	check(size && size.width === 400 && size.height === 240, `run.snap: the design frame drawn into a render target, a PNG ${JSON.stringify(size)}`);
	const saved = () => pg.evaluate(async () => {
		await window.studioWeb.saved?.();
		const d = await (await (await navigator.storage.getDirectory()).getDirectoryHandle('projects')).getDirectoryHandle('agent');
		return (await (await d.getFileHandle('app.helder')).getFile()).text();
	});
	check((await saved()).includes('Hi there'), 'the patch saved in OPFS');
	check(await press(pg, 'Undo'), 'the patch undone (the header\'s Undo)');
	await pg.waitForTimeout(300);
	check((await saved()).includes('>Hello<'), 'the undo saved');
	const list = JSON.parse((await run('project.list', {})).content[0].text);
	check(list.open === 'agent' && list.projects.includes('agent'), 'project.list: ' + JSON.stringify(list));
	const z = 'z.' + deflateRawSync(JSON.stringify({ name: 'agent', files: { 'app.helder': design.replace('Hello', 'Deflated') } })).toString('base64url');
	await pg.goto(base + '#import=' + z);
	await pg.waitForURL(/project=agent-2/, { timeout: 30000 });
	await ready(pg);
	await event(pg, 'designs-shown');
	const tree2 = await pg.evaluate(() => window.studioWeb.call('run.tree', { screen: 'app.helder#Card' }));
	check(tree2.content[0].text.includes('"Deflated"'), 'an #import=z. link (deflate-raw) opened as agent-2');
	// (a Haxe app from a link: no preview module, built at its open by the compiler's worker)
	const ex = path.join(here, '../../examples/signup');
	const code = { 'Signup.hx': await readFile(path.join(ex, 'Signup.hx'), 'utf8'), 'Signup.story.hx': await readFile(path.join(ex, 'Signup.story.hx'), 'utf8') };
	await pg.goto(base + '#import=' + Buffer.from(JSON.stringify({ name: 'signup', files: code })).toString('base64url'));
	await pg.waitForURL(/project=signup/, { timeout: 30000 });
	await ready(pg);
	const all = await event(pg, 'all-shown', () => true, 240000);
	const shot = await pg.evaluate(() => window.studioWeb.call('run.snap', { screen: 'Sign up/Light' }));
	const signup = shot.content.find((c) => c.type === 'image');
	check(all && png(signup?.data ?? '')?.width === 420, `a Haxe app from an #import= link built at its open, its screens shown in ${all?.ms} ms, run.snap ${shot.content.at(-1).text}`);
	await ctx.close();
}

// ---- phone (touch, compact: the inspector a bottom sheet, the screens' list a drawer)
{
	const pg = await page({ width: 390, height: 844 }, true);
	const shown = await openExample(pg, 'Todo');
	check(shown && shown.screens === 4, `phone: all 4 screens shown (${shown?.ms} ms)`);
	await pg.waitForTimeout(400);
	await golden(pg, 'phone-overview');
	await pg.touchscreen.tap(195, 320);
	await pg.waitForTimeout(1600);
	await golden(pg, 'phone-zoomed');
	await pg.touchscreen.tap(60, 120);
	const sel = await event(pg, 'selected');
	check(sel && sel.tag === 'text' && sel.screen === 'Todo/Three items', 'phone: the title tapped and selected: ' + JSON.stringify(sel && [sel.screen, sel.tag, sel.rect]));
	await pg.waitForTimeout(500);
	await pg.screenshot({ path: path.join(out, 'phone-selected.png') });
	const p = await recolour(pg, 110, 782, true);
	numbers.push(['phone patch', p]);
	check(red(await pixel(pg, 60, 120)), 'phone: the title red in the studio\'s canvas');
	// two fingers apart over the canvas: zoomed in
	const cdp = await pg.context().newCDPSession(pg);
	const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
	const at = (d) => [{ x: 195 - d, y: 300, id: 1 }, { x: 195 + d, y: 300, id: 2 }];
	await touch('touchStart', at(30));
	for (let d = 34; d <= 90; d += 4) {
		await touch('touchMove', at(d));
		await pg.waitForTimeout(16);
	}
	await touch('touchEnd', []);
	const pinch = await event(pg, 'pinched', () => true, 5000);
	check(pinch && pinch.k > 1, `phone: a pinch zooms the canvas in (k ${pinch?.k})`);
	await pg.waitForTimeout(300);
	await pg.screenshot({ path: path.join(out, 'phone-pinched.png') });
	check(await press(pg, 'Screens'), 'phone: the screens\' drawer opened from the header');
	await pg.waitForTimeout(600);
	await pg.screenshot({ path: path.join(out, 'phone-drawer.png') });
	check(await press(pg, 'Todo/Done'), 'phone: a screen chosen in the drawer');
	await pg.waitForTimeout(1600);
	await pg.screenshot({ path: path.join(out, 'phone-done.png') });
	await pg.context().close();
}

// ---- 50 screens
{
	const pg = await page({ width: 1180, height: 740 }, false);
	const t0 = Date.now();
	const shown = await openExample(pg, '50 screens');
	const wall = Date.now() - t0;
	const by = await pg.evaluate(() => window.studioWeb.framesByScreen);
	check(shown && shown.screens === 50 && Object.keys(by).length === 50, `50 screens: all shown, ${shown?.ms} ms after opening (${wall} ms from the welcome's click, the page loaded again)`);
	const stats = await pg.evaluate(() => window.studioWeb.stats());
	const started = await pg.evaluate(() => window.studioWeb.started);
	numbers.push(['50 screens', stats, started, shown, wall]);
	await pg.waitForTimeout(300);
	await pg.screenshot({ path: path.join(out, 'screens50-overview.png') });
	// one zoomed into: the others' frames stop (only the screens in view draw)
	const before = await pg.evaluate(() => ({ ...window.studioWeb.framesByScreen }));
	await pg.mouse.click(Number(process.env.S50_X ?? 330), Number(process.env.S50_Y ?? 150));
	await pg.waitForTimeout(2000);
	const after = await pg.evaluate(() => window.studioWeb.framesByScreen);
	const drew = Object.keys(after).filter((k) => after[k] !== before[k]).length;
	check(drew <= 10, `50 screens: one zoomed into, ${drew} screen(s) drew since (the ones in view)`);
	await pg.screenshot({ path: path.join(out, 'screens50-zoomed.png') });
	await pg.context().close();
}

await browser.close();
server.close();

// ---- the numbers
const mb = (b) => (b / 1048576).toFixed(1) + ' MB';
const lines = ['| | |', '|---|---|'];
for (const n of numbers) {
	if (n[0] === 'todo (4 screens)') lines.push(`| todo, 4 screens: the preview's worker started (its module instantiated, main run) | ${Math.round(n[2]?.ms)} ms (${n[2]?.backend}) |`, `| todo: the project opened to every screen shown | ${n[3]?.ms} ms |`);
	else if (n[0] === '50 screens') lines.push(`| 50 screens: the project opened to every screen shown | ${n[3]?.ms} ms (${n[4]} ms from the click, the page loaded again) |`,
		`| 50 screens: memory: the preview's module, the studio's, the page's JavaScript | ${mb(n[1].preview)}, ${mb(n[1].studio)}, ${mb(n[1].js)} |`);
	else if (n[0] === 'structural') lines.push(`| the compiler's worker started (helder.compiler.web: downloaded, compiled, warmed) | ${n[3]?.total} ms |`,
		`| a structural edit (a padding added): built by the compiler's worker (its first build), the preview swapped in with its state | ${n[1]?.ms} ms |`,
		`| the same undone (the attribute removed): a warm build, swapped in | ${n[4]?.ms} ms |`);
	else lines.push(`| ${n[0]}: an inspector's colour to the preview's frame (a live literal) | ${n[1]?.ms} ms, ${n[1]?.frames} studio frame(s) |`);
}
const table = lines.join('\n');
console.log(table);
await writeFile(path.join(out, 'results.md'), table + '\n');
console.log(`studio-web: ${checks} checks, ${failures ? failures + ' FAILED' : 'ok'}`);
process.exit(failures ? 1 : 0);
