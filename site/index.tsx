// The site: one page listing helder's examples, each a card of its title,
// summary and tags (its header), those that run in a browser with a Play
// button starting their wasm32 build in the page. TSX through helder's
// TypeScript frontend, rendered to HTML by helder.web's static renderer
// when this program runs (site/build.mjs builds it after the examples and
// writes the JSON it imports: their headers and builds). An example with a
// page.json has a page of its own too, <id>.html: its demo, description,
// numbers (site/numbers.mjs's, measured headless in CI, read from
// numbers.json by numbers.js; real devices' from page.json; three.js' for
// the same scene) and credits.
import { Static, Island } from "helder/web";
import site from "../bin/site-build/examples.json";

interface Demo {
	// canvas (width x height) or sound (no canvas)
	kind: string;
	width: number;
	height: number;
}

// an Android build of it, for phones: the file, its size, the commit it was built from
interface Apk {
	file: string;
	bytes: number;
	commit: string;
}

// a row of the numbers: on a real device (page.json's), or a slot filled from numbers.json
interface Device {
	device: string;
	firstFrameMs: string;
	// (all the Play button fetches: the module too, gzipped; "–" when not measured)
	fetchedGzMB: string;
	downloadMB: string;
	memoryMB: string;
	p50Ms: string;
	p99Ms: string;
}

// the same scene elsewhere (three.js' example): what it downloads
interface Compare {
	what: string;
	url: string;
	downloadMB: string;
	note: string;
}

interface Page {
	description: string[];
	compare: Compare[];
	devices: Device[];
	credits: string[];
	// what numbers.mjs plays: the program's args beyond the data folder (a scene each, by label)
	numbers: string[];
	// how long numbers.mjs plays it (0: its default)
	seconds: number;
}

interface Example {
	id: string;
	title: string;
	summary: string;
	tags: string[];
	source: string;
	demo: Demo | null;
	// (its build: the module, the browser modules it imports, fonts, its assets' list; "" and [] without a demo)
	wasm: string;
	imports: string[];
	fonts: string[];
	assets: string;
	apk: Apk | null;
	// the program's arguments (a data folder's URL), its page (null: none), its data's bytes
	args: string[];
	page: Page | null;
	dataBytes: number;
}

const examples = site.examples as Example[];
const playable = examples.filter(e => e.demo !== null).length;
// the demos with a page of their own (page.json), linked from the top of the index
// (the most striking first; any other after them, in the index's order)
const SHOWCASE = ["sponza", "gltf-showcase", "planet", "particles", "instancing", "physics-stress", "bunnymark"];
const rank = (e: Example) => SHOWCASE.indexOf(e.id) < 0 ? SHOWCASE.length : SHOWCASE.indexOf(e.id);
const showcase = examples.filter(e => e.page !== null).sort((a, b) => rank(a) - rank(b));
const RUNNER = "helder/os/browser.mjs";

const CSS = `
:root { color-scheme: light dark; --bg: #f6f6f4; --fg: #1b1b1f; --muted: #5b5b66; --card: #fff; --line: #e3e3e0; --accent: #1d4ed8;
	--chip: #eeeef0; --stage: #141418; }
@media (prefers-color-scheme: dark) {
	:root { --bg: #0e0e11; --fg: #ececf1; --muted: #a1a1ad; --card: #18181d; --line: #2a2a31; --accent: #8ab4ff; --chip: #24242b; --stage: #050507; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 17px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
	-webkit-text-size-adjust: 100%; }
a { color: var(--accent); }
header, main, footer { max-width: 1240px; margin: 0 auto; padding: 0 16px; }
header { padding-top: 40px; }
h1 { font-size: clamp(2.2rem, 7vw, 3.2rem); line-height: 1.1; margin: 0 0 12px; letter-spacing: -0.02em; }
.lead { margin: 0 0 8px; max-width: 64ch; color: var(--muted); }
main { display: grid; grid-template-columns: 1fr; gap: 16px; align-items: start; padding-top: 24px; padding-bottom: 32px; }
@media (min-width: 760px) { main { grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 20px; } }
.card { min-width: 0; background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; }
.card:has(hxmc-island[data-loading]), .card:has(hxmc-island[data-hydrated]), .card:has(hxmc-island[data-error]) { grid-column: 1 / -1; }
.body { padding: 14px 16px 16px; }
h2 { font-size: 1.2rem; line-height: 1.3; margin: 0 0 6px; }
.summary { margin: 0 0 10px; }
.tags { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 10px; padding: 0; list-style: none; }
.tags li { background: var(--chip); color: var(--muted); border-radius: 999px; padding: 1px 10px; font-size: 0.85rem; }
.links { margin: 0; font-size: 0.95rem; }
.stage { background: var(--stage); }
.stage hxmc-island { display: block; position: relative; margin: 0 auto; max-width: var(--w); }
.stage canvas { display: block; width: 100%; height: auto; aspect-ratio: var(--ratio); outline: none; }
.sound hxmc-island { display: grid; place-items: center; min-height: 120px; max-width: none; }
.play { font: inherit; font-weight: 600; font-size: 1.05rem; color: #111; background: #fff; border: 0; border-radius: 999px; padding: 10px 22px;
	cursor: pointer; box-shadow: 0 2px 12px rgba(0, 0, 0, .35); }
.play:hover, .play:focus-visible { background: #dbe7ff; }
.stage:not(.sound) .play { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); }
.size { position: absolute; right: 10px; bottom: 8px; color: #9a9aa6; font-size: 0.8rem; }
.sound .size { display: none; }
hxmc-island[data-loading] .play, hxmc-island[data-hydrated] .play, hxmc-island[data-error] .play,
hxmc-island[data-loading] .size, hxmc-island[data-hydrated] .size, hxmc-island[data-error] .size { display: none; }
hxmc-island[data-loading]::after, hxmc-island[data-error]::after { position: absolute; inset: 0; display: grid; place-items: center; padding: 16px;
	color: #e8e8ee; text-align: center; pointer-events: none; }
hxmc-island[data-loading]::after { content: "Loading…"; }
hxmc-island[data-error]::after { content: "Could not run: " attr(data-error); color: #ffb4b4; }
.sound hxmc-island[data-hydrated]::after { content: "Played"; color: #e8e8ee; }
.full, .exit { position: absolute; z-index: 2; font: inherit; font-size: 0.85rem; font-weight: 600; color: #111; background: #ffffffe0; border: 0;
	border-radius: 999px; padding: 6px 14px; cursor: pointer; box-shadow: 0 2px 10px rgba(0, 0, 0, .3); display: none; }
.full { right: 10px; top: 10px; }
.exit { left: 50%; transform: translateX(-50%); top: calc(env(safe-area-inset-top) + 8px); padding: 6px 12px; opacity: 0.85; }
.stage { position: relative; }
.stage:has(hxmc-island[data-hydrated]) .full { display: block; }
.stage.expanded { position: fixed; inset: 0; z-index: 1000; height: 100vh; height: 100dvh; display: flex; align-items: stretch; justify-content: center;
	padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); }
.stage.expanded hxmc-island { max-width: none; width: 100%; height: 100%; margin: 0; }
.stage.expanded canvas { width: 100%; height: 100%; aspect-ratio: auto; touch-action: none; }
.stage.expanded .full, .stage.expanded:has(hxmc-island[data-hydrated]) .full { display: none; }
.stage.expanded .exit { display: block; }
html.playing, html.playing body { overflow: hidden; overscroll-behavior: none; }
.apk { margin: 8px 0 10px; font-size: 0.95rem; }
.apk a { font-weight: 600; }
.apk span { color: var(--muted); font-size: 0.85rem; }
footer { padding-bottom: 40px; color: var(--muted); font-size: 0.95rem; }
code { font-size: 0.92em; }
.showcase { margin: 18px 0 4px; }
.showcase h2 { font-size: 1rem; color: var(--muted); font-weight: 600; margin: 0 0 8px; }
.showcase ul { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 10px; margin: 0; padding: 0; list-style: none; }
.showcase a { display: block; height: 100%; box-sizing: border-box; padding: 10px 12px; border: 1px solid var(--line); border-radius: 10px;
	background: var(--chip); color: inherit; text-decoration: none; }
.showcase a:hover, .showcase a:focus-visible { border-color: var(--muted); }
.showcase strong { display: block; margin-bottom: 2px; }
.showcase span { display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden; color: var(--muted);
	font-size: 0.88rem; line-height: 1.35; }
main.page { display: block; max-width: 1000px; }
.page h2 { margin-top: 22px; }
.muted { color: var(--muted); font-size: 0.92rem; }
.numbers { width: 100%; border-collapse: collapse; font-size: 0.92rem; display: block; overflow-x: auto; }
.numbers th, .numbers td { padding: 6px 8px; border-bottom: 1px solid var(--line); text-align: right; white-space: nowrap; }
.numbers th[scope=row] { text-align: left; white-space: normal; min-width: 180px; }
`;

// the canvas (or, for a sound, none) its Play button starts: a WebAssembly island loaded on the first click
function Stage(props: { ex: Example }) {
	const ex = props.ex;
	const demo = ex.demo as Demo;
	const sound = demo.kind === "sound";
	const style = sound ? "" : "--w:" + demo.width + "px;--ratio:" + demo.width + "/" + demo.height;
	const game = ex.tags.indexOf("game") >= 0;
	return <div class={sound ? "stage sound" : "stage"} style={style} data-width={"" + demo.width} data-height={"" + demo.height} data-game={game ? "" : undefined}>
		<Island.Wasm src={ex.wasm} id={"play-" + ex.id} load="click" runner={RUNNER} imports={ex.imports} fonts={ex.fonts} assets={ex.assets === "" ? undefined : ex.assets}
			args={ex.args.length > 0 ? ex.args : undefined} stop={ex.args.length > 0 ? "offscreen" : undefined}
			canvas={!sound} width={demo.width} height={demo.height}>
			<button class="play" type="button" aria-label={"Play " + ex.title}>{sound ? "▶ Play sound" : "▶ Play"}</button>
			<span class="size">{demo.width + "×" + demo.height}</span>
		</Island.Wasm>
		{sound ? null : <button class="full" type="button" aria-label={"Play " + ex.title + " full screen"}>⛶ Full screen</button>}
		{sound ? null : <button class="exit" type="button" aria-label="Leave full screen">✕</button>}
	</div>;
}

// its Android build's link, size and commit
function Download(props: { apk: Apk }) {
	const a = props.apk;
	const mb = Math.round(a.bytes / 104857.6) / 10;
	return <p class="apk"><a href={a.file} download="">Download for Android (APK)</a> <span>{mb + " MB · built from " + a.commit}</span></p>;
}

function Card(props: { ex: Example }) {
	const ex = props.ex;
	return <article class="card" id={ex.id}>
		{ex.demo !== null ? <Stage ex={ex} /> : null}
		<div class="body">
			<h2>{ex.title}</h2>
			<p class="summary">{ex.summary}</p>
			<ul class="tags">{ex.tags.map(t => <li>{t}</li>)}</ul>
			{ex.apk !== null ? <Download apk={ex.apk as Apk} /> : null}
			<p class="links">{ex.page !== null ? <a href={ex.id + ".html"}>Details and numbers</a> : null}{ex.page !== null ? " · " : ""}<a href={ex.source}>Source</a></p>
		</div>
	</article>;
}

// the numbers' row of a device (a real one's, from page.json; CI's: slots numbers.js fills)
function Row(props: { d: Device, slot: string }) {
	const d = props.d;
	const cell = (key: string, value: string) => props.slot === "" ? <td>{value}</td> : <td data-num={props.slot + "." + key}>{value}</td>;
	return <tr>
		<th scope="row">{d.device}</th>
		{cell("firstFrameMs", d.firstFrameMs)}
		{cell("fetchedGzMB", d.fetchedGzMB)}
		{cell("downloadMB", d.downloadMB)}
		{cell("memoryMB", d.memoryMB)}
		{cell("p50Ms", d.p50Ms)}
		{cell("p99Ms", d.p99Ms)}
	</tr>;
}

function Numbers(props: { ex: Example }) {
	const ex = props.ex;
	const page = ex.page as Page;
	const scenes = page.numbers.length > 0 ? page.numbers : [""];
	const ci = (label: string): Device => ({ device: "CI: headless Chromium, SwiftShader (software)" + (label === "" ? "" : ", " + label), firstFrameMs: "…", fetchedGzMB: "…",
		downloadMB: "…", memoryMB: "…", p50Ms: "…", p99Ms: "…" });
	return <table class="numbers">
		<thead><tr><th scope="col"></th><th scope="col">First frame (ms)</th><th scope="col">Fetched, gzipped (MB)</th><th scope="col">Data download (MB)</th><th scope="col">GPU textures (MB)</th>
			<th scope="col">Frame p50 (ms)</th><th scope="col">Frame p99 (ms)</th></tr></thead>
		<tbody>
			{scenes.map(label => <Row d={ci(label)} slot={ex.id + (label === "" ? "" : "." + label)} />)}
			{page.devices.map(d => <Row d={d} slot="" />)}
		</tbody>
	</table>;
}

function DemoPage(props: { ex: Example }) {
	const ex = props.ex;
	const page = ex.page as Page;
	return <html lang="en">
		<head>
			<meta charset="utf-8" />
			<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
			<title>{ex.title + " · helder examples"}</title>
			<meta name="description" content={ex.summary} />
			<style>{CSS}</style>
			<script src="stage.js" defer></script>
			<script src="loader.js" defer></script>
			<script src="numbers.js" defer></script>
		</head>
		<body>
			<header>
				<p class="lead"><a href="index.html">← helder examples</a></p>
				<h1>{ex.title}</h1>
				<p class="lead">{ex.summary}</p>
			</header>
			<main class="page">
				<article class="card" id={ex.id}>
					{ex.demo !== null ? <Stage ex={ex} /> : null}
					<div class="body">
						{page.description.map(p => <p>{p}</p>)}
						<h2>Numbers</h2>
						<p class="muted">The first frame: from the program's start to its first frame (a model's fetch, decoding and upload included); fetched: all the Play
							button downloads, the module, its browser modules, fonts and assets, gzipped; the data download: what the program fetches
							beyond the module{ex.dataBytes > 0 ? " (" + Math.round(ex.dataBytes / 104857.6) / 10 + " MB of data beside it)" : ""}; GPU textures:
							the bytes of the textures alive (helder.gfx's Device.textureBytes); frame times from its overlay. CI's are headless software
							rendering, not a phone's or a desktop's GPU; the real devices' rows are measured by hand.</p>
						<Numbers ex={ex} />
						{page.compare.length > 0 ? <h2>The same elsewhere</h2> : null}
						{page.compare.length > 0 ? <ul>{page.compare.map(c => <li><a href={c.url}>{c.what}</a>{": " + c.downloadMB + " MB downloaded. " + c.note}</li>)}</ul> : null}
						<h2>Credits</h2>
						<ul>{page.credits.map(c => <li>{c}</li>)}</ul>
						<ul class="tags">{ex.tags.map(t => <li>{t}</li>)}</ul>
						<p class="links"><a href={ex.source}>Source</a></p>
					</div>
				</article>
			</main>
		</body>
	</html>;
}

for (const ex of examples) {
	if (ex.page !== null) Static.write(site.dir + "/" + ex.id + ".html", Static.document(<DemoPage ex={ex} />));
}

Static.write(site.out, Static.document(<html lang="en">
	<head>
		<meta charset="utf-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
		<title>helder examples</title>
		<meta name="description" content="helder's examples: games and apps in Haxe and TypeScript on the hxmc compiler, running in the page as WebAssembly." />
		<style>{CSS}</style>
		<script src="stage.js" defer></script>
		<script src="loader.js" defer></script>
	</head>
	<body>
		<header>
			<h1>helder</h1>
			<p class="lead">An app and game stack in Haxe, with a TypeScript frontend, compiled by hxmc to native code and WebAssembly.
				These are its examples; the {playable} with a Play button run here, in your browser.</p>
			<p class="lead"><a href={site.repository}>Source on GitHub</a></p>
			<nav class="showcase" aria-label="Showcase">
				<h2>Showcase</h2>
				<ul>{showcase.map(ex => <li><a href={ex.id + ".html"}><strong>{ex.title}</strong><span>{ex.summary}</span></a></li>)}</ul>
			</nav>
		</header>
		<main>
			{examples.map(ex => <Card ex={ex} />)}
		</main>
		<footer>
			<p>This page is <code>site/index.tsx</code>: TSX through helder's TypeScript frontend, rendered to HTML by helder.web's static renderer.</p>
		</footer>
	</body>
</html>));
