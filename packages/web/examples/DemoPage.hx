import hxmc.view.*;
import hxmc.web.*;

// The demo page, rendered at build time (natively or on Eval):
//   <tool> -cp packages/view/src -cp packages/web/src -cp packages/web/examples \
//     -D hxmc.view.renderer.html=hxmc.web.StaticRenderer --run DemoPage <out dir>
// writes <out dir>/index.html: static text, three JavaScript islands
// (DemoIslands: a counter, one whose markup differs on the client, one
// calling a WebAssembly module) and, below the fold, a WebAssembly island:
// gfx's cube on a canvas (cube.wasm, packages/gfx/examples/Cube.hx), shown
// with its source. Next to it: loader.js, islands.js (DemoBundle),
// lab.wasm (Lab), cube.wasm, and os/, gfx/, web/ (the packages' browser.mjs
// and imports.mjs).
class DemoPage implements Markup {
	static function Source(props:{path:String}):View
		return <details class="source"><summary>{haxe.io.Path.withoutDirectory(props.path)}</summary>
			<pre><code>{sys.io.File.getContent(props.path)}</code></pre></details>;

	static function main() {
		var out = Sys.args()[0];
		Static.write(out + "/index.html", Static.document(<html lang="en">
			<head>
				<meta charset="utf-8"/>
				<title>@hxmc/web demo</title>
				<script src="loader.js" defer></script>
			</head>
			<body>
				<h1>@hxmc/web</h1>
				<p class="static">A static page with islands &amp; a <code>{"<canvas>"}</code>.</p>
				<DemoIslands.Counter start={3} items={["one", "two"]}/>
				<DemoIslands.Mismatch/>
				<DemoIslands.Lab wasm="lab.wasm"/>
				<Counter.Island start={0}/>
				<div class="spacer" style={{height: "3000px"}}></div>
				<Island.Wasm src="cube.wasm" id="cube" imports={["os/imports.mjs", "gfx/imports.mjs"]} width={256} height={192}>
					<p>gfx's cube, drawn by a wasm32-wasi module once it scrolls into view.</p>
				</Island.Wasm>
				<Source path="packages/gfx/examples/Cube.hx"/>
			</body>
		</html>));
	}
}
