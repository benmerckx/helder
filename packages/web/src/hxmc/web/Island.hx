package hxmc.web;

import hxmc.view.View;

// when the loader hydrates an island (data-load)
enum abstract Load(String) to String {
	// once it scrolls into view (IntersectionObserver)
	var Visible = "visible";
	// once the browser is idle (requestIdleCallback)
	var Idle = "idle";
	// at once, when the page has loaded
	var Eager = "load";
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
// (data-load); the loader (packages/web/loader.js) loads the bundle then,
// which hydrates the island from its props. Props are JSON: numbers,
// strings, booleans, arrays and objects of them.
//
// A WebAssembly island (Island.Wasm) is a canvas the loader hands to a
// wasm32-wasi module, run by @hxmc/os's browser.mjs with the imports of the
// packages it uses: a ui or gfx canvas inside a page.
class Island<P> implements hxmc.view.Markup {
	// the islands defined, by name
	public static final all = new Map<String, Island<Dynamic>>();
	// the default runner of WebAssembly islands (@hxmc/os's browser.mjs)
	public static var runner = "os/browser.mjs";

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
		if (all.exists(name)) throw 'hxmc.web: two islands named $name';
		var i = new Island(name, component, options);
		all.set(name, cast i);
		// (on the client, the component alone; a JavaScript program with the
		// static renderer too, -D hxmc.view.renderer.html=..., renders pages)
		#if (js && !hxmc.view.renderer.html)
		return props -> i.content(props);
		#else
		return props -> i.render(props);
		#end
	}

	// the island in its element
	public function render(props:P):View
		return <hxmc-island data-island={name} data-props={haxe.Json.stringify(props)} data-load={(load : String)} data-src={script}>{content(props)}</hxmc-island>;

	// its content: the component called when mounted (what hydration mounts)
	public function content(props:P):View
		return <Call component={cast component} props={props}/>;

	static function Call(props:{component:Dynamic->Any, props:Dynamic}):Any
		return props.component(props.props);

	// a WebAssembly island: a canvas (width x height, when given) the loader
	// hands to src, a wasm32-wasi module, run by runner (Island.runner) with
	// imports (each package's imports.mjs, as browser.mjs takes them) and
	// args; its id names it (Wasm.island); children shown with the canvas
	// (a caption, what shows before it runs)
	public static function Wasm(props:{
		src:String,
		?imports:Array<String>,
		?args:Array<String>,
		?runner:String,
		?load:Load,
		?id:String,
		?width:Int,
		?height:Int,
		?children:Any
	}):View {
		var load:String = props.load == null ? Visible : props.load;
		return <hxmc-island id={props.id} data-wasm={props.src} data-runner={props.runner == null ? runner : props.runner}
			data-imports={haxe.Json.stringify(props.imports == null ? [] : props.imports)}
			data-args={props.args == null ? null : haxe.Json.stringify(props.args)} data-load={load}>
			<canvas width={props.width} height={props.height}></canvas>
			{props.children}
		</hxmc-island>;
	}
}
