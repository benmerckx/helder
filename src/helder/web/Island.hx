package helder.web;

import helder.view.View;

// when the loader hydrates an island (data-load)
enum abstract Load(String) to String {
	// once it scrolls into view (IntersectionObserver)
	var Visible = "visible";
	// once the browser is idle (requestIdleCallback)
	var Idle = "idle";
	// at once, when the page has loaded
	var Eager = "load";
	// on the first click or key press inside it (a sound: the browsers start
	// audio only after one)
	var Click = "click";
}

// when a WebAssembly island stops its program (loader.js, data-stop)
enum abstract Stop(String) to String {
	// once it has scrolled out of view: its GPU memory and canvas given back
	var Offscreen = "offscreen";
}

typedef IslandOptions = {
	// the JavaScript bundle that hydrates it (Islands.start in its main)
	?script:String,
	?load:Load
}

// Islands: the interactive parts of a static page. An island is a component
// defined once, in code both the page's build (the static renderer) and the
// island's bundle (JavaScript, the DOM renderer) compile:
//
//   class Demo implements Markup {
//     static function CounterView(props:{start:Int}):View ...
//     public static final Counter = Island.define("counter", CounterView, {script: "islands.js", load: Visible});
//   }
//
//   // the page (static): <Demo.Counter start={3}/>
//   // the bundle's main (JavaScript): Islands.start([Demo.Counter]);
//
// On the page it is rendered in an element <hxmc-island> carrying its name,
// its props as JSON (data-props), its bundle (data-src) and when to load it
// (data-load); the loader (src/helder/web/loader.js) loads the bundle then,
// which hydrates the island from its props. Props are JSON: numbers,
// strings, booleans, arrays and objects of them.
//
// A WebAssembly island (Island.Wasm) is a canvas the loader hands to a
// wasm32-wasi module, run by helder.os's browser.mjs with the imports of the
// packages it uses: a ui or gfx canvas inside a page.
class Island<P> implements helder.view.Markup {
	// the islands defined, by name
	public static final all = new Map<String, Island<Dynamic>>();
	// the default runner of WebAssembly islands (helder.os's browser.mjs)
	public static var runner = "os/browser.mjs";
	// the address written for each file an island loads (its bundle, a
	// module, the runner, imports, fonts), from the name it was given: a
	// site sets it per page, for pages in folders and for its build in the
	// address (a cache-busting query)
	public static var url:String->String = s -> s;

	public final name:String;
	public final component:P->Any;
	public final script:Null<String>;
	public final load:Load;

	function new(name:String, component:P->Any, options:Null<IslandOptions>) {
		this.name = name;
		this.component = component;
		this.script = options == null ? null : options.script;
		this.load = options == null || options.load == null ? Visible : options.load;
	}

	// an island: a component, its props written into the page, hydrated there by its bundle
	public static function define<P>(name:String, component:P->Any, ?options:IslandOptions):P->Any {
		if (all.exists(name)) throw 'helder.web: two islands named $name';
		var i = new Island(name, component, options);
		all.set(name, cast i);
		// (in a page the static renderer writes, the island in its element; in
		// the DOM, the component alone: chosen by the renderer mounting it)
		return props -> helder.view.Render.pass == helder.view.Render.idOf(helder.web.StaticRenderer) ? i.render(props) : i.content(props);
	}

	// the island in its element
	public function render(props:P):View {
		// (its content as hydration mounts it: not a region)
		var c = content(props);
		return <hxmc-island data-island={name} data-props={haxe.Json.stringify(props)} data-load={(load : String)} data-src={script == null ? null : url(script)}>{c}</hxmc-island>;
	}

	// its content: the component called when mounted (what hydration mounts)
	public function content(props:P):View
		return <Call component={cast component} props={props}/>;

	static function Call(props:{component:Dynamic->Any, props:Dynamic}):Any
		return props.component(props.props);

	// a WebAssembly island: a canvas (width x height, when given) the loader
	// hands to src, a wasm32-wasi module, run by runner (Island.runner) with
	// imports (each package's imports.mjs, as browser.mjs takes them) and
	// args, and fonts (files helder.text may use: a browser gives a module
	// none); its id names it (Wasm.island); children shown with the canvas
	// (a caption, what shows before it runs); assets: the URL of the build's
	// <module>.assets.json (helder.asset's: the files it reads before main,
	// fetched with the module); canvas false: none (a sound);
	// stop Offscreen: stopped once out of view, its GPU memory given back,
	// and run again as load says (loader.js)
	public static function Wasm(props:{
		src:String,
		?imports:Array<String>,
		?args:Array<String>,
		?runner:String,
		?load:Load,
		?id:String,
		?width:Int,
		?height:Int,
		?fonts:Array<String>,
		?assets:String,
		?canvas:Bool,
		?stop:Stop,
		?children:Any
	}):View {
		var load:String = props.load == null ? Visible : props.load;
		return <hxmc-island id={props.id} data-wasm={url(props.src)} data-runner={url(props.runner == null ? runner : props.runner)}
			data-imports={haxe.Json.stringify(props.imports == null ? [] : props.imports.map(url))}
			data-fonts={props.fonts == null ? null : haxe.Json.stringify(props.fonts.map(url))}
			data-args={props.args == null ? null : haxe.Json.stringify(props.args)} data-assets={props.assets == null ? null : url(props.assets)}
			data-load={load} data-stop={props.stop}>
			{props.canvas == false ? null : <canvas width={props.width} height={props.height}></canvas>}
			{props.children}
		</hxmc-island>;
	}
}
