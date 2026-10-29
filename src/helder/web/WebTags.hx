package helder.web;

import helder.view.Render;
import helder.view.View;
import helder.web.Island.Load;

// helder.web's boundary tags, for a page's markup (the DOM renderer's, the
// static renderer's): import helder.web.WebTags.*
//
//   <main>
//     <h1>Todo</h1>
//     <Surface src="todo.wasm" fonts={["fonts/DejaVuSans.ttf"]} class="app"/>
//   </main>
//
// <Surface> is a ui program on the page: a <canvas> the page's styles size
// (100% of its element, the element's size the page's CSS), running src, a
// wasm32-wasi module whose root is ui's <Surface> (UiWindow.run: it takes
// this canvas and follows its size). The static renderer writes it as an
// island (Island.Wasm's element, loader.js starts it: load says when); the
// DOM renderer starts it once mounted (WasmModule.load). A page can hold
// several. Another renderer's markup has no <Surface> of helder.web's (an
// error naming it: ui's is UiWindow.Surface).
@:renderer(helder.web.DomRenderer, helder.web.StaticRenderer)
class WebTags implements helder.view.Markup {
	// the browser modules a ui program imports (helder.os's runner loads them)
	public static final UI_IMPORTS = ["os/imports.mjs", "gfx/imports.mjs", "text/imports.mjs", "ui/imports.mjs"];

	public static function Surface(props:{
		src:String,
		?imports:Array<String>,
		?fonts:Array<String>,
		?args:Array<String>,
		?runner:String,
		?load:Load,
		?id:String,
		?className:String,
		?style:String,
		?children:Any
	}):View {
		var imports = props.imports ?? UI_IMPORTS;
		var url = Island.url, runner = props.runner ?? Island.runner;
		#if js
		// (the DOM's: started here, not by the loader, which saw the page before it)
		if (Render.pass == Render.idOf(helder.web.DomRenderer))
			return <div id={props.id} class={props.className} style={props.style ?? "position:relative"}>
				<canvas style="display:block;width:100%;height:100%" ref={(c:js.html.CanvasElement) -> helder.view.graph.Graph.onSettled(() -> WasmModule.load(url(props.src),
					{runner: url(runner), imports: imports.map(url), fonts: props.fonts == null ? null : props.fonts.map(url), args: props.args, canvas: c}))}></canvas>
				{props.children}
			</div>;
		#end
		var load:String = props.load ?? Eager;
		return <hxmc-island id={props.id} class={props.className} style={props.style} data-wasm={url(props.src)} data-runner={url(runner)}
			data-imports={haxe.Json.stringify(imports.map(url))} data-fonts={props.fonts == null ? null : haxe.Json.stringify(props.fonts.map(url))}
			data-args={props.args == null ? null : haxe.Json.stringify(props.args)} data-load={load}>
			<canvas style="display:block;width:100%;height:100%"></canvas>
			{props.children}
		</hxmc-island>;
	}
}
