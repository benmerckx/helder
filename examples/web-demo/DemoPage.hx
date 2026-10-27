import helder.view.*;
import helder.web.*;
import helder.web.WebTags.*;

// The demo page, rendered at build time (natively or on Eval):
//   <tool> -cp src -cp examples/web-demo --run DemoPage <out dir>
// writes <out dir>/index.html: static text, three JavaScript islands
// (DemoIslands: a counter, one whose markup differs on the client, one
// calling a WebAssembly module) and, below the fold, a WebAssembly island:
// gfx's cube on a canvas (cube.wasm, examples/cube/Cube.hx), shown
// with its source; then ui's counter (examples/counter: its root a
// <Surface>) as a <Surface> of the page, its size the page's styles. Next to
// it: loader.js, islands.js (DemoBundle), lab.wasm (Lab), cube.wasm,
// counter-ui.wasm, and os/, gfx/, text/, ui/, web/ (the packages'
// browser.mjs and imports.mjs), fonts/.
class DemoPage implements Markup {
	static function Source(props:{path:String}):View
		return <details class="source"><summary>{haxe.io.Path.withoutDirectory(props.path)}</summary>
			<pre><code>{sys.io.File.getContent(props.path)}</code></pre></details>;

	static function main() {
		var out = Sys.args()[0];
		Static.write(out + "/index.html", Static.document(<html lang="en">
			<head>
				<meta charset="utf-8"/>
				<title>helder.web demo</title>
				<script src="loader.js" defer></script>
			</head>
			<body>
				<h1>helder.web</h1>
				<p class="static">A static page with islands &amp; a <code>{"<canvas>"}</code>.</p>
				<DemoIslands.Counter start={3} items={["one", "two"]}/>
				<DemoIslands.Mismatch/>
				<DemoIslands.Lab wasm="lab.wasm"/>
				<Counter.Island start={0}/>
				<div class="spacer" style={{height: "3000px"}}></div>
				<Island.Wasm src="cube.wasm" id="cube" imports={["os/imports.mjs", "gfx/imports.mjs"]} width={256} height={192}>
					<p>gfx's cube, drawn by a wasm32-wasi module once it scrolls into view.</p>
				</Island.Wasm>
				<Source path="examples/cube/Cube.hx"/>
				<Surface src="counter-ui.wasm" id="counter-ui" fonts={["fonts/DejaVuSans.ttf"]} style="display:block;width:320px;height:200px" load={Visible}>
					<p>ui's counter, drawn by a wasm32-wasi module on a canvas the page sizes.</p>
				</Surface>
				<Source path="examples/counter/Counter.hx"/>
			</body>
		</html>));
	}
}
