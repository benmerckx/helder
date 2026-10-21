// The landing page: the universe (a planet per example, on its package's
// orbit around the compiler; a trail on narrow screens) and a world (the
// example compiled in this tab by the compiler's worker, compiler.js, and
// run on the stage by @hxmc/os's browser.mjs; its source, editable; a
// native download for any target, compiled the same way). #/<example id>
// opens a world.
import { sky } from './sky.js';
import { zip } from './zip.js';

const $ = (id) => document.getElementById(id);
const sk = sky($('sky'));
const reduced = matchMedia('(prefers-reduced-motion: reduce)');

const PACKAGES = {
	gfx: 'a portable GPU API, shaders in Haxe',
	physics: 'a small rigid-body core',
	'3d': 'glTF scenes, PBR, animation',
	ui: 'a UI toolkit drawn on the GPU',
	theme: 'shadcn/ui looks for ui',
	os: 'windows, input, audio',
};
// the orbits, inner to outer
const RINGS = ['os', 'theme', 'physics', '3d', 'ui', 'gfx'];
const COLORS = { gfx: '#22d3ee', physics: '#fb923c', '3d': '#a78bfa', ui: '#4ade80', theme: '#f472b6', os: '#facc15' };
const TARGET_LABELS = {
	'linux-x86_64': ['Linux', 'x86-64', '🐧'],
	'linux-arm64': ['Linux', 'ARM64', '🐧'],
	'macos-arm64': ['macOS', 'Apple silicon', '⌘'],
	'macos-x86_64': ['macOS', 'Intel', '⌘'],
	'windows-x86_64': ['Windows', 'x86-64', '⊞'],
	'windows-arm64': ['Windows', 'ARM64', '⊞'],
};

// ---- what the visitor has done (this browser only) ----

const save = (() => {
	let s = { visited: [], native: [], counts: {} };
	try {
		s = { ...s, ...JSON.parse(localStorage.getItem('universe:v1') ?? '{}') };
	} catch {}
	return {
		s,
		write() {
			try {
				localStorage.setItem('universe:v1', JSON.stringify(s));
			} catch {}
		},
	};
})();

function toast(html) {
	const t = document.createElement('div');
	t.className = 'toast';
	t.innerHTML = html;
	$('toasts').append(t);
	setTimeout(() => t.remove(), 3300);
}

// ---- the compiler ----

let worker = null, ready = null, coreState = 'asleep';
const pending = new Map();
let listeners = { progress: null, files: null };
let nextId = 1;

function setCore(state, text) {
	coreState = state;
	const c = $('core');
	c.classList.toggle('loading', state === 'loading');
	c.classList.toggle('ready', state === 'ready');
	$('core-state').textContent = text;
}

function wake() {
	if (ready) return ready;
	if (!supported()) {
		setCore('asleep', 'this browser cannot run the compiler');
		return (ready = Promise.reject(new Error('This browser lacks WebAssembly exception handling (exnref): Chrome 137+, Firefox 131+ or Safari 18.4+ run the compiler.')));
	}
	setCore('loading', 'waking up…');
	worker = new Worker(new URL('compiler.js', import.meta.url), { type: 'module' });
	const loads = {};
	worker.onmessage = ({ data }) => {
		if (data.type === 'progress') {
			loads[data.what] = data;
			const all = Object.values(loads);
			const loaded = all.reduce((n, l) => n + l.loaded, 0), total = all.reduce((n, l) => n + Math.max(l.total, l.loaded), 0);
			if (coreState === 'loading') setCore('loading', `downloading ${(loaded / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MB`);
			listeners.progress?.(data, loaded, total);
		} else if (data.type === 'files') listeners.files?.(data.files);
		else if (data.type === 'ready') pending.get('init')?.resolve();
		else if (data.type === 'done') pending.get(data.id)?.resolve(data);
		else if (data.type === 'error') (pending.get(data.id ?? 'init') ?? pending.get('init'))?.reject(new Error(data.message));
	};
	ready = new Promise((resolve, reject) => pending.set('init', { resolve, reject })).then(
		() => setCore('ready', 'compiler ready · 100% wasm'),
		(e) => {
			setCore('asleep', 'the compiler failed to start');
			throw e;
		},
	);
	worker.postMessage({ type: 'init' });
	return ready;
}

// exception handling with exnref, which haxe.wasm uses: a function with an
// exnref local and a try_table validates
function supported() {
	try {
		return WebAssembly.validate(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 0x60, 0, 0, 3, 2, 1, 0, 10, 10, 1, 8, 1, 1, 0x69, 0x1f, 0x40, 0, 0x0b, 0x0b]));
	} catch {
		return false;
	}
}

// one build at a time (the worker runs them in turn anyway)
let queue = Promise.resolve();
function build(example, target, edits) {
	const run = async () => {
		await wake();
		const id = nextId++;
		const p = new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
		worker.postMessage({ type: 'compile', id, example, target, edits });
		try {
			return await p;
		} finally {
			pending.delete(id);
		}
	};
	const r = queue.then(run, run);
	queue = r.catch(() => {});
	return r;
}

// ---- the forge: the loader over the stage ----

const forge = {
	el: $('forge'),
	phase: null,
	reads: 0,
	writes: 0,
	expect: 500,
	show(label, expect) {
		this.el.hidden = false;
		this.reads = this.writes = 0;
		this.expect = expect || 500;
		this.phase = null;
		$('ticker').replaceChildren();
		for (const s of ['fetch', 'parse', 'emit', 'link']) this.ring(s, 0);
		this.set('fetch', label);
		$('forge-count').textContent = '…';
		sk.hold(0.35);
	},
	hide() {
		this.el.hidden = true;
		sk.hold(0);
	},
	ring(name, f) {
		const c = $('ring-' + name), len = 2 * Math.PI * c.r.baseVal.value;
		c.style.strokeDasharray = `${Math.max(0, Math.min(1, f)) * len} ${len}`;
	},
	set(phase, label) {
		const order = ['fetch', 'parse', 'emit', 'link'];
		if (this.phase !== phase) {
			const i = order.indexOf(phase);
			for (const li of this.el.querySelectorAll('.phases li')) {
				const j = order.indexOf(li.dataset.phase);
				li.classList.toggle('on', j === i);
				li.classList.toggle('done', j < i);
			}
			for (const s of order.slice(0, order.indexOf(phase))) this.ring(s, 1);
			this.phase = phase;
		}
		if (label) $('forge-phase').textContent = label;
	},
	files(list) {
		const t = $('ticker');
		for (const [path, writing] of list) {
			if (writing) this.writes++;
			else this.reads++;
			if (!writing && this.phase === 'fetch') this.set('parse', 'parsing · typing');
			if (writing && path.endsWith('.o') && this.phase !== 'emit') this.set('emit', 'emitting machine code');
		}
		const last = list.slice(-3);
		for (const [path, writing] of last) {
			const d = document.createElement('div');
			d.textContent = (writing ? '→ ' : '') + path.replace(/^\/lib\/(src\/packages\/|std\/|hxmc-std\/)?/, '').replace(/^\/work\/out\/[^/]+\/[^/]+\//, '');
			if (writing) d.className = 'w';
			t.append(d);
		}
		while (t.children.length > 5) t.firstChild.remove();
		$('forge-count').textContent = this.phase === 'emit' ? `${this.writes}` : `${this.reads}`;
		this.ring('parse', this.reads / this.expect);
		if (this.phase === 'emit') this.ring('emit', Math.min(0.95, this.writes / Math.max(20, this.expect / 12)));
		sk.kick(0.02 * list.length);
		if (!reduced.matches) this.sparks(Math.min(4, list.length));
	},
	sparks(n) {
		const box = this.el.getBoundingClientRect();
		const color = getComputedStyle($('world')).getPropertyValue('--c1') || '#22d3ee';
		for (let i = 0; i < n; i++) {
			const s = document.createElement('i');
			s.className = 'spark';
			const a = Math.random() * Math.PI * 2, r = Math.max(box.width, box.height) * 0.55;
			s.style.setProperty('--x', `${Math.cos(a) * r}px`);
			s.style.setProperty('--y', `${Math.sin(a) * r}px`);
			s.style.background = color;
			s.style.boxShadow = `0 0 8px ${color}`;
			this.el.append(s);
			setTimeout(() => s.remove(), 750);
		}
	},
	progress(data, loaded, total) {
		this.ring('fetch', total ? loaded / total : 0);
		$('forge-count').textContent = `${(loaded / 1048576).toFixed(1)}`;
		this.set('fetch', `MB of compiler · ${data.what}`);
	},
};

// ---- the universe ----

let examples = [], manifest = null;
const planets = new Map();
let layout = 'orbit', spin = 0, spinSpeed = 1, hovered = null;

function buildUniverse() {
	const sys = $('system');
	for (const pkg of RINGS.slice().reverse()) {
		const list = examples.filter((e) => e.pkg === pkg);
		if (!list.length) continue;
		const head = document.createElement('div');
		head.className = `system-head pkg-${pkg}`;
		head.innerHTML = `<h3>${pkg}</h3><p>${PACKAGES[pkg] ?? ''}</p>`;
		sys.append(head);
		for (const e of list) {
			const b = document.createElement('button');
			b.type = 'button';
			b.className = `planet pkg-${e.pkg}`;
			b.dataset.id = e.id;
			b.setAttribute('aria-label', `${e.title}: ${e.summary}`);
			const size = 46 + Math.min(30, (e.summary.length % 7) * 4 + (e.pkg === 'ui' || e.pkg === '3d' ? 10 : 0));
			b.style.setProperty('--size', `${size}px`);
			if (e.pkg === '3d' || e.id === 'gfx-instances' || e.id === 'physics-walker') b.style.setProperty('--ring', '1');
			b.innerHTML = `<span class="orb"></span><span class="text"><span class="name"></span><span class="meta"></span></span>`;
			b.querySelector('.name').textContent = e.title;
			b.querySelector('.meta').textContent = e.summary;
			if (save.s.visited.includes(e.id)) b.classList.add('visited');
			b.addEventListener('click', () => enter(e));
			b.addEventListener('pointerenter', () => hover(e, b));
			b.addEventListener('pointerleave', () => hover(null));
			b.addEventListener('focus', () => hover(e, b));
			b.addEventListener('blur', () => hover(null));
			sys.append(b);
			planets.set(e.id, { e, el: b, ring: RINGS.indexOf(pkg), i: list.indexOf(e), n: list.length });
		}
	}
	const card = document.createElement('div');
	card.className = 'card';
	card.id = 'card';
	sys.append(card);
	hud();
}

function hover(e, el) {
	hovered = e;
	const card = $('card');
	if (!e || layout !== 'orbit') {
		card.classList.remove('on');
		return;
	}
	card.innerHTML = `<h3></h3><p></p><div class="go">${save.s.visited.includes(e.id) ? 'visited · enter again' : 'enter world'} ▸</div>`;
	card.querySelector('h3').textContent = e.title;
	card.querySelector('p').textContent = e.summary;
	const r = el.getBoundingClientRect();
	const x = Math.min(innerWidth - card.offsetWidth - 12, Math.max(12, r.left + r.width / 2 - 150));
	const below = r.bottom + 10 + card.offsetHeight < innerHeight;
	card.style.left = `${x}px`;
	card.style.top = `${below ? r.bottom + 10 : r.top - card.offsetHeight - 10}px`;
	card.classList.add('on');
	wake().catch(() => {});
}

function hud() {
	const v = save.s.visited.filter((id) => examples.some((e) => e.id === id)).length;
	$('progress-hud').innerHTML = `worlds <b>${v}/${examples.length}</b>${save.s.native.length ? ` · native <b>${save.s.native.length}</b>` : ''}`;
}

// the orbits: ellipses around the core, each package's planets spread on its own
function place(now) {
	requestAnimationFrame(place);
	if ($('universe').hidden || layout !== 'orbit') return;
	const w = innerWidth, h = innerHeight;
	const cx = w * (w > 1100 ? 0.58 : 0.5), cy = h * (w > 1100 ? 0.52 : 0.6);
	const maxRx = Math.min(w * (w > 1100 ? 0.4 : 0.46), (h * 0.42) / 0.42);
	const minRx = 110;
	spinSpeed += ((hovered ? 0 : 1) - spinSpeed) * 0.08;
	if (!reduced.matches) spin += 0.0009 * spinSpeed;
	const orbits = [];
	for (const p of planets.values()) {
		const k = p.ring / (RINGS.length - 1);
		const rx = minRx + (maxRx - minRx) * k, ry = rx * 0.42;
		const dir = p.ring % 2 ? 1 : -1;
		const a = spin * dir * (1.4 - k * 0.6) + (p.i / p.n) * Math.PI * 2 + p.ring * 0.9;
		const depth = Math.sin(a);
		const x = cx + rx * Math.cos(a), y = cy + ry * depth;
		const s = 0.72 + 0.38 * (depth + 1) / 2;
		p.el.style.transform = `translate(${x}px, ${y}px) translate(-50%, -30%) scale(${s})`;
		p.el.style.zIndex = depth > 0 ? 3 : 1;
		p.el.style.filter = depth < -0.3 ? `brightness(${0.55 + 0.45 * (1 + depth)})` : '';
		if (p.i === 0) orbits.push({ cx, cy, rx, ry, color: COLORS[p.e.pkg] });
	}
	sk.orbits = orbits;
	const core = $('core');
	core.style.left = `${cx}px`;
	core.style.top = `${cy}px`;
}

function relayout() {
	const narrow = innerWidth < 760 || innerHeight < 560;
	layout = narrow ? 'trail' : 'orbit';
	$('universe').classList.toggle('trail', narrow);
	if (narrow) {
		sk.orbits = [];
		for (const p of planets.values()) p.el.style.cssText = p.el.style.cssText.replace(/transform:[^;]*;?|z-index:[^;]*;?|filter:[^;]*;?/g, '');
		const core = $('core');
		core.style.left = core.style.top = '';
		$('system').before(core);
	} else $('system').after($('core'));
}

// ---- a world ----

let current = null, host = null, edits = {}, files = [], active = 0, lastBuild = null, target = null, runToken = 0;

async function enter(e, { push = true } = {}) {
	if (push) history.pushState({ id: e.id }, '', `#/${e.id}`);
	current = e;
	edits = {};
	lastBuild = null;
	sk.kick(1.2);
	hover(null);
	const world = $('world');
	world.className = `view pkg-${e.pkg}`;
	world.style.setProperty('--c1', COLORS[e.pkg]);
	$('universe').hidden = true;
	world.hidden = false;
	$('world-title').textContent = e.title;
	$('world-summary').textContent = e.summary;
	$('world-pkg').textContent = `@hxmc/${e.pkg}`;
	const [cw, ch] = e.demo.canvas ?? [16, 9];
	$('stage').style.setProperty('--aspect', `${cw / ch}`);
	$('console').replaceChildren();
	closeSource();
	files = null;
	if (!save.s.visited.includes(e.id)) {
		save.s.visited.push(e.id);
		save.write();
		planets.get(e.id)?.el.classList.add('visited');
		hud();
		const n = save.s.visited.length;
		if (n === 1) setTimeout(() => toast('🪐 <b>First world</b> · compiled right here, in this tab'), 900);
		else if (n === examples.length) setTimeout(() => toast('🌌 <b>Every world visited</b> · the whole universe, from source'), 900);
	}
	stop();
	if (e.demo.sound) {
		// (audio starts after a tap: the browsers' rule)
		$('play').hidden = false;
		$('play').querySelector('span').textContent = 'Tap to compile and play';
		return;
	}
	$('play').hidden = true;
	await runWorld();
}

function leave({ push = true } = {}) {
	if (push && location.hash) history.pushState(null, '', location.pathname + location.search);
	stop();
	closeSource();
	current = null;
	$('world').hidden = true;
	$('universe').hidden = false;
	sk.calm = false;
	sk.kick(0.8);
	setTimeout(() => planets.get(lastLeft)?.el.focus({ preventScroll: true }), 50);
}
let lastLeft = null;

function stop() {
	runToken++;
	try {
		host?.dispose();
		host?.os?.stop?.();
	} catch {}
	host = null;
	$('screen').replaceChildren();
}

function log(text, cls) {
	const c = $('console');
	const d = document.createElement('div');
	if (cls) d.className = cls;
	// (an error with a position: a link to that line of the source)
	const m = /(\/lib\/src\/(packages\/[^:]+\.hx)):(\d+):/.exec(text);
	if (m && current && [current.source, ...current.sources].includes(m[2])) {
		const a = document.createElement('a');
		a.textContent = text;
		a.onclick = () => openSource(m[2], +m[3]);
		d.append(a);
	} else d.textContent = text;
	c.append(d);
	while (c.children.length > 200) c.firstChild.remove();
	c.scrollTop = c.scrollHeight;
}

async function runWorld() {
	const e = current;
	const token = ++runToken;
	stop();
	runToken = token;
	$('run').disabled = true;
	sk.calm = false;
	listeners.progress = (d, l, t) => forge.progress(d, l, t);
	listeners.files = (f) => forge.files(f);
	forge.show(ready && coreState === 'ready' ? 'warming up' : 'downloading the compiler', save.s.counts[e.id]);
	let r;
	try {
		r = await build(e, 'wasm32-wasi', edits);
	} catch (err) {
		forge.hide();
		$('run').disabled = false;
		log(String(err.message ?? err), 'err');
		return;
	}
	if (token !== runToken || current !== e) return;
	$('console').replaceChildren();
	if (!r.ok) {
		forge.hide();
		$('run').disabled = false;
		for (const l of r.log) log(l, 'err');
		if (!r.log.length) log('the build failed', 'err');
		return;
	}
	save.s.counts[e.id] = forge.reads;
	save.write();
	forge.set('link', 'linked');
	forge.ring('emit', 1);
	forge.ring('link', 1);
	$('forge-count').textContent = `${(r.ms / 1000).toFixed(1)}s`;
	log(`compiled ${e.main}.hx → ${(r.bytes.length / 1024).toFixed(0)} KB of wasm in ${(r.ms / 1000).toFixed(2)} s, in this tab`, 'ok');
	lastBuild = r;
	await new Promise((ok) => setTimeout(ok, reduced.matches ? 0 : 380));
	if (token !== runToken) return;
	forge.hide();
	sk.kick(0.6);
	await launch(e, r, token);
	$('run').disabled = false;
}

async function launch(e, r, token) {
	const { run } = await import('./os/browser.mjs');
	if (token !== runToken) return;
	const screen = $('screen');
	let canvas = null;
	if (e.demo.canvas) {
		canvas = document.createElement('canvas');
		[canvas.width, canvas.height] = e.demo.canvas;
		canvas.tabIndex = 0;
		screen.append(canvas);
	} else {
		const s = document.createElement('div');
		s.className = 'sound';
		s.innerHTML = '<div>' + '<i></i>'.repeat(9) + '</div>';
		s.querySelectorAll('i').forEach((i, k) => (i.style.animationDelay = `${k * 0.08}s`));
		screen.append(s);
		setTimeout(() => s.remove(), 2600);
	}
	const fonts = e.fonts ? ['fonts/DejaVuSans.ttf', 'fonts/DejaVuSans-Bold.ttf'].map((f) => new URL(f, location.href).href) : [];
	const assetFiles = Object.fromEntries(r.assets.map(([p, b]) => [p, URL.createObjectURL(new Blob([b]))]));
	try {
		const out = await run(r.bytes, {
			imports: e.imports.map((i) => new URL(i, location.href).href),
			canvas, fonts, files: assetFiles, track: true, antialias: true,
			touchAction: 'none',
			stdout: (l) => log(l),
			stderr: (l) => log(l, 'err'),
			onError: (err) => log(String(err?.message ?? err), 'err'),
		});
		if (token !== runToken) {
			out.host.dispose();
			return;
		}
		host = out.host;
		sk.calm = true;
		if (out.exitCode) log(`exited with code ${out.exitCode}`, 'err');
		canvas?.focus({ preventScroll: true });
	} catch (err) {
		log(String(err?.message ?? err), 'err');
	}
}

// ---- the source ----

async function openSource(path, line) {
	const e = current;
	if (!files) {
		files = await Promise.all([e.source, ...e.sources].map(async (p) => ({ path: p, text: await sourceOf(p) })));
		if (current !== e) return;
	}
	const tabs = $('tabs');
	tabs.replaceChildren();
	files.forEach((f, i) => {
		const b = document.createElement('button');
		b.type = 'button';
		b.role = 'tab';
		b.textContent = f.path.split('/').pop();
		b.onclick = () => showFile(i);
		if (edits[f.path] !== undefined) b.classList.add('edited');
		tabs.append(b);
	});
	$('source').hidden = false;
	$('show-source').setAttribute('aria-expanded', 'true');
	const i = path ? Math.max(0, files.findIndex((f) => f.path === path)) : active;
	showFile(i, line);
}

function showFile(i, line) {
	active = i;
	const f = files[i];
	const code = $('code');
	code.value = edits[f.path] ?? f.text;
	[...$('tabs').children].forEach((b, k) => b.setAttribute('aria-selected', String(k === i)));
	if (line) {
		const lines = code.value.split('\n');
		const start = lines.slice(0, line - 1).join('\n').length + (line > 1 ? 1 : 0);
		code.focus();
		code.setSelectionRange(start, start + (lines[line - 1]?.length ?? 0));
		code.scrollTop = Math.max(0, (line - 6) * parseFloat(getComputedStyle(code).lineHeight));
	}
}

function closeSource() {
	$('source').hidden = true;
	$('show-source').setAttribute('aria-expanded', 'false');
}

// the source of a file: the pack the worker has, read again here (small, cached)
let srcPack = null;
async function sourceOf(path) {
	srcPack ??= fetch('src.pack').then((r) => r.arrayBuffer()).then(async (b) => new Map((await import('./wasi.js')).unpack(b)));
	return new TextDecoder().decode((await srcPack).get(path));
}

$('code').addEventListener('input', () => {
	const f = files[active];
	edits[f.path] = $('code').value;
	$('tabs').children[active].classList.add('edited');
});
$('code').addEventListener('keydown', (ev) => {
	if (ev.key === 'Tab' && !ev.shiftKey) {
		ev.preventDefault();
		document.execCommand('insertText', false, '\t');
	}
	if ((ev.metaKey || ev.ctrlKey) && ev.key === 'Enter') {
		ev.preventDefault();
		runWorld();
	}
});

// ---- the native download ----

async function detectTarget() {
	const ua = navigator.userAgent;
	let os = /Windows/.test(ua) ? 'windows' : /iPhone|iPad|iPod|Android/.test(ua) ? null : /Mac OS X|Macintosh/.test(ua) ? 'macos' : /Linux|X11|CrOS/.test(ua) ? 'linux' : null;
	// (an iPad asks for the desktop site: a Mac with a touch screen)
	if (os === 'macos' && navigator.maxTouchPoints > 1) os = null;
	let arch = /aarch64|arm64/i.test(ua) ? 'arm64' : null;
	try {
		const h = await navigator.userAgentData?.getHighEntropyValues(['architecture', 'bitness']);
		if (h?.architecture === 'arm') arch = 'arm64';
		else if (h?.architecture === 'x86') arch = 'x86_64';
	} catch {}
	// (Safari says Intel on Apple silicon too: most Macs now are arm64)
	arch ??= os === 'macos' ? 'arm64' : 'x86_64';
	return { target: `${os ?? 'windows'}-${arch}`, guessed: !os };
}

function renderTargets() {
	const ul = $('targets');
	ul.replaceChildren();
	for (const t of manifest.targets) {
		const [os, cpu, icon] = TARGET_LABELS[t] ?? [t, '', ''];
		const li = document.createElement('li');
		li.role = 'option';
		li.tabIndex = -1;
		li.dataset.target = t;
		li.setAttribute('aria-selected', String(t === target.target));
		li.innerHTML = `<span class="os-icon">${icon}</span><span>${os} · ${cpu}</span>${t === detected?.target && !detected.guessed ? '<small>this machine</small>' : ''}`;
		li.onclick = () => {
			target = { target: t, guessed: false };
			pick(false);
			labelDownload();
			download();
		};
		ul.append(li);
	}
}

function labelDownload() {
	const [os, cpu] = TARGET_LABELS[target.target];
	$('dl-target').textContent = target.guessed ? 'pick your desktop ▸' : `${os} · ${cpu}`;
}

function pick(open) {
	const ul = $('targets');
	ul.hidden = !open;
	$('pick').setAttribute('aria-expanded', String(open));
	if (open) {
		renderTargets();
		(ul.querySelector('[aria-selected="true"]') ?? ul.firstChild)?.focus();
	}
}

$('targets').addEventListener('keydown', (ev) => {
	const items = [...$('targets').children];
	const i = items.indexOf(document.activeElement);
	if (ev.key === 'ArrowDown') items[(i + 1) % items.length].focus();
	else if (ev.key === 'ArrowUp') items[(i - 1 + items.length) % items.length].focus();
	else if (ev.key === 'Enter' || ev.key === ' ') document.activeElement.click();
	else if (ev.key === 'Escape') {
		pick(false);
		$('pick').focus();
	} else return;
	ev.preventDefault();
});

async function download() {
	const e = current;
	if (!e) return;
	if (target.guessed) {
		pick(true);
		return;
	}
	const t = target.target;
	const [os, cpu] = TARGET_LABELS[t];
	const btn = $('download');
	btn.disabled = $('pick').disabled = true;
	const was = $('screen').childElementCount > 0;
	listeners.progress = (d, l, tot) => forge.progress(d, l, tot);
	listeners.files = (f) => forge.files(f);
	forge.show(`forging for ${os} · ${cpu}`, save.s.counts[`${e.id}@native`]);
	forge.set('fetch', `fetching the ${os} runtime`);
	let r;
	try {
		r = await build(e, t, edits);
	} catch (err) {
		log(String(err.message ?? err), 'err');
	} finally {
		btn.disabled = $('pick').disabled = false;
	}
	forge.hide();
	if (!r) return;
	if (!r.ok) {
		for (const l of r.log) log(l, 'err');
		return;
	}
	save.s.counts[`${e.id}@native`] = forge.reads;
	log(`compiled ${e.main}.hx for ${os} ${cpu} → ${(r.bytes.length / 1024).toFixed(0)} KB in ${(r.ms / 1000).toFixed(2)} s, in this tab`, 'ok');
	const windows = t.startsWith('windows');
	let blob, name;
	if (windows && !r.assets.length) {
		blob = new Blob([r.bytes], { type: 'application/vnd.microsoft.portable-executable' });
		name = `${e.main}.exe`;
	} else {
		const entries = [{ name: r.file, data: r.bytes, mode: 0o755 }, ...r.assets.map(([p, b]) => ({ name: p, data: b }))];
		blob = new Blob([zip(entries)], { type: 'application/zip' });
		name = `${e.main}-${t}.zip`;
	}
	const a = document.createElement('a');
	a.href = URL.createObjectURL(blob);
	a.download = name;
	document.body.append(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(a.href), 30000);
	if (!save.s.native.includes(t)) {
		save.s.native.push(t);
		toast(`⚡ <b>Went native</b> · ${os} ${cpu}${save.s.native.length > 1 ? ` · ${save.s.native.length} targets` : ''}`);
	}
	save.write();
	hud();
	howToRun(e, t, name);
	if (!was && !e.demo.sound) runWorld();
}

function howToRun(e, t, name) {
	const [os, cpu] = TARGET_LABELS[t];
	const exe = e.main;
	const body = {
		macos: `<p>Unzip it, then in a terminal: <code>xattr -d com.apple.quarantine ${exe} && ./${exe}</code></p><p>It's signed ad hoc, not notarized, so macOS quarantines a download until you say otherwise. Or right-click it and choose <em>Open</em>.</p>`,
		linux: `<p>Unzip it and run <code>./${exe}</code>. It loads your GPU's drivers through glibc (X11, GL or Vulkan via Mesa).</p>`,
		windows: `<p>Run <code>${name}</code>. SmartScreen doesn't know this program yet: <em>More info</em>, then <em>Run anyway</em>.</p>`,
	}[t.split('-')[0]];
	$('sheet-title').textContent = `${e.title} for ${os} · ${cpu}`;
	$('sheet-body').innerHTML = `<p>Compiled from the same Haxe source by the compiler in this tab: no server, no toolchain.</p>${body}`;
	$('sheet').hidden = false;
	$('sheet-ok').focus();
}

// ---- wiring ----

let detected = null;

$('back').onclick = () => {
	lastLeft = current?.id;
	leave();
};
$('run').onclick = () => {
	$('play').hidden = true;
	runWorld();
};
$('play').onclick = () => {
	$('play').hidden = true;
	runWorld();
};
$('show-source').onclick = () => ($('source').hidden ? openSource() : closeSource());
$('source-close').onclick = closeSource;
$('download').onclick = download;
$('pick').onclick = () => pick($('targets').hidden);
$('sheet-ok').onclick = () => ($('sheet').hidden = true);
$('sheet').onclick = (ev) => ev.target === $('sheet') && ($('sheet').hidden = true);
$('core').onclick = () => {
	sk.kick(0.6);
	wake().catch((e) => toast(e.message));
};
addEventListener('keydown', (ev) => {
	if (ev.key !== 'Escape') return;
	if (!$('sheet').hidden) $('sheet').hidden = true;
	else if (!$('targets').hidden) pick(false);
	else if (!$('source').hidden) closeSource();
	else if (current && document.activeElement?.tagName !== 'CANVAS') {
		lastLeft = current.id;
		leave();
	}
});
addEventListener('click', (ev) => {
	if (!$('targets').hidden && !ev.target.closest('.split')) pick(false);
});
addEventListener('popstate', () => route(false));
addEventListener('resize', relayout);
// (the compiler wakes on the first touch anywhere: by the time a world is
// picked, it is mostly downloaded)
addEventListener('pointerdown', () => wake().catch(() => {}), { once: true });

function route(push) {
	const id = location.hash.replace(/^#\/?/, '');
	const e = examples.find((x) => x.id === id);
	if (e) enter(e, { push });
	else if (current) leave({ push: false });
}

async function main() {
	manifest = await (await fetch('manifest.json')).json();
	examples = manifest.examples;
	$('version').textContent = manifest.hxmc.version.replace(/^.*nightly\./, '');
	buildUniverse();
	relayout();
	requestAnimationFrame(place);
	detected = await detectTarget();
	target = { ...detected };
	labelDownload();
	if (!supported()) setCore('asleep', 'needs a newer browser (WebAssembly exnref)');
	route(false);
}

main();
