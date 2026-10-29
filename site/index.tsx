// The site: one page listing helder's examples, each a card of its title,
// summary and tags (its header), those that run in a browser with a Play
// button starting their wasm32 build in the page. TSX through helder's
// TypeScript frontend, rendered to HTML by helder.web's static renderer
// when this program runs (site/build.mjs builds it after the examples and
// writes the JSON it imports: their headers and builds).
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
}

const examples = site.examples as Example[];
const playable = examples.filter(e => e.demo !== null).length;
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
			<p class="links"><a href={ex.source}>Source</a></p>
		</div>
	</article>;
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
		</header>
		<main>
			{examples.map(ex => <Card ex={ex} />)}
		</main>
		<footer>
			<p>This page is <code>site/index.tsx</code>: TSX through helder's TypeScript frontend, rendered to HTML by helder.web's static renderer.</p>
		</footer>
	</body>
</html>));
