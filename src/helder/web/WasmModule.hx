package helder.web;

#if js
import haxe.io.Bytes;
import js.lib.Promise;
import js.lib.Uint8Array;

typedef WasmOptions = {
	// helder.os's browser.mjs (Island.runner by default)
	?runner:String,
	// the packages' imports.mjs (src/helder/web/imports.mjs for Exports)
	?imports:Array<String>,
	?args:Array<String>,
	// the canvas of its first window (an element or its id)
	?canvas:Dynamic
}

// A wasm32-wasi module running in the page, seen from JavaScript: its
// Exports called by name (an Exports class's functions do it, typed),
// bytes copied in and out of its memory.
//
//   WasmModule.load("lab.wasm", {imports: ["web/imports.mjs"]}).then(m -> {
//     LabExports.module = m;
//     trace(LabExports.sum(1, 2));
//   });
class WasmModule {
	// browser.mjs's host (memory(), call, web.exports) and the instance
	public final host:Dynamic;
	public final instance:Dynamic;

	public function new(host:Dynamic, instance:Dynamic) {
		this.host = host;
		this.instance = instance;
	}

	// runs a module (its main first; the module stays for calls after it returns)
	public static function load(wasm:String, ?options:WasmOptions):Promise<WasmModule> {
		var o:WasmOptions = options == null ? {} : options;
		var runner = new js.html.URL(o.runner == null ? Island.runner : o.runner, js.Browser.document.baseURI).href;
		var url = new js.html.URL(wasm, js.Browser.document.baseURI).href;
		return (js.Syntax.code("import({0})", runner) : Promise<Dynamic>).then(m -> (m.run(url, {imports: o.imports, args: o.args, canvas: o.canvas}) : Promise<Dynamic>))
			.then(r -> new WasmModule(r.host, r.instance));
	}

	// the module a WebAssembly island of the page runs (Island.Wasm, by its id), once it has started
	public static function island(id:String):Promise<WasmModule> {
		var p:Null<Promise<Dynamic>> = js.Syntax.code("(globalThis.hxmcWasm || {})[{0}]", id);
		if (p == null) return Promise.reject('helder.web: no WebAssembly island $id (not started yet?)');
		return p.then(r -> new WasmModule(r.host, r.instance));
	}

	// whether it exports name
	public function exports(name:String):Bool
		return host.web != null && js.Syntax.field(host.web.exports, name) != null;

	// an export called with numbers (Int: i32, Float: f64); its result
	public function call(name:String, args:Array<Dynamic>):Dynamic {
		var f:Null<Int> = host.web == null ? null : js.Syntax.field(host.web.exports, name);
		if (f == null) throw 'helder.web: the module exports no $name';
		return js.Syntax.code("{0}.call({1}, ...{2})", host, f, args);
	}

	// b copied into a new block of the module's memory (free it)
	public function copyIn(b:Bytes):{address:Int, length:Int} {
		var p:Int = call("__alloc", [b.length]);
		new Uint8Array(host.memory().buffer, p, b.length).set(new Uint8Array(b.getData(), 0, b.length));
		return {address: p, length: b.length};
	}

	// a result block's bytes (its length, then them), copied; the block freed
	public function copyOut(p:Int):Null<Bytes> {
		if (p == 0) return null;
		var buffer:js.lib.ArrayBuffer = host.memory().buffer;
		var n = new js.lib.DataView(buffer).getInt32(p, true);
		var b = Bytes.alloc(n);
		new Uint8Array(b.getData()).set(new Uint8Array(buffer, p + 4, n));
		free(p);
		return b;
	}

	public function free(p:Int)
		call("__free", [p]);
}
#end
