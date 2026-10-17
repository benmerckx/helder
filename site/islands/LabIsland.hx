import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.web.*;

// The examples' JavaScript calling WebAssembly (@hxmc/web's Exports): a
// JavaScript island (lab.js, site/client/LabBundle.hx) loads lab.wasm
// (packages/web/examples/Lab.hx) and calls its LabExports, typed on both
// sides: strings, numbers and bytes in bulk.
class LabIsland implements Markup {
	static function LabView(props:{wasm:String, imports:Array<String>}):View {
		var ready = signal(false);
		var name = signal("page");
		var a = signal(2), b = signal(3);
		var inverted = signal("");
		onMount(() -> {
			#if js
			WasmModule.load(props.wasm, {imports: props.imports}).then(m -> {
				LabExports.module = m;
				ready.value = true;
			}, e -> {
				inverted.value = "failed: " + e;
				return false;
			});
			#end
		});
		function invert() {
			#if js
			var bytes = haxe.io.Bytes.alloc(1 << 20);
			for (i in 0...bytes.length)
				bytes.set(i, i & 255);
			var t0 = js.Browser.window.performance.now();
			var out = LabExports.invert(bytes);
			var ms = js.Browser.window.performance.now() - t0;
			var ok = out.length == bytes.length && out.get(1) == 254 && out.get(bytes.length - 1) == 0;
			inverted.value = '1 MB inverted ${ok ? "correctly" : "wrongly"} in ${Math.round(ms * 10) / 10} ms (copied in and out)';
			#end
		}
		function number(s:String):Int {
			var n = Std.parseInt(s);
			return n == null ? 0 : n;
		}
		return <div class="lab">
			<label>Name <input class="lab-name" value={name} onInput={(e:Dynamic) -> name.value = e.target.value}/></label>
			<p class="lab-out lab-greet"><code>{() -> ready.value ? 'greet("${name.value}")' : "greet"}</code> {() -> ready.value ? greet(name.value) : "loading lab.wasm…"}</p>
			<p class="lab-row">
				<input class="lab-a" type="number" value={a} onInput={(e:Dynamic) -> a.value = number(e.target.value)}/>
				<span>+</span>
				<input class="lab-b" type="number" value={b} onInput={(e:Dynamic) -> b.value = number(e.target.value)}/>
				<span>=</span>
				<b class="lab-sum">{() -> ready.value ? Std.string(sum(a.value, b.value)) : "…"}</b>
			</p>
			<p class="lab-row"><button type="button" class="lab-invert" disabled={() -> !ready.value} onClick={() -> invert()}>Invert 1 MB in wasm</button>
				<span class="lab-inverted">{inverted}</span></p>
		</div>;
	}

	// (the module's functions: only the bundle calls them, once it is loaded)
	static function greet(name:String):String
		return #if js LabExports.greet(name) #else "" #end;

	static function sum(a:Int, b:Int):Int
		return #if js LabExports.sum(a, b) #else 0 #end;

	public static final Lab = Island.define("lab", LabView, {script: "lab.js", load: Visible});
}
