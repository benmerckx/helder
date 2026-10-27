import helder.view.*;
import helder.view.Flow.*;
import helder.view.Reactive.*;
import helder.web.*;

// The demo page's islands, in code both builds compile: the page's
// (DemoPage, the static renderer) and the islands' bundle (DemoBundle,
// JavaScript, the DOM renderer)
class DemoIslands implements Markup {
	// a counter: a signal, a list, a reactive attribute and style, SVG
	static function CounterView(props:{start:Int, items:Array<String>}):View {
		var count = signal(props.start);
		var items = signal(props.items);
		var name = signal("");
		return <section class="counter" data-count={count} style={() -> {color: count.value % 2 == 0 ? "green" : "purple"}}>
			<p>Count: <b class="count">{count}</b> (started at {props.start})</p>
			<button class="inc" onClick={() -> {
				count.value++;
				items.value = items.value.concat(["item " + count.value]);
			}}>+1</button>
			<input class="name" value={name} onInput={(e:Dynamic) -> name.value = e.target.value}/>
			<p class="hello">Hello{() -> name.value == "" ? "" : ", " + name.value}!</p>
			<ul><For each={items} render={(i:String) -> <li>{i}</li>}/></ul>
			<Show when={() -> count.value > props.start} fallback={<i class="untouched">untouched</i>}><i class="touched">touched</i></Show>
			<svg width="20" height="20"><circle cx="10" cy="10" r={() -> 4 + count.value % 6}/></svg>
		</section>;
	}

	public static final Counter = Island.define("counter", CounterView, {script: "islands.js", load: Eager});

	// rendered differently by the page and by the bundle: hydration falls back
	static function MismatchView(props:{}):View {
		#if js
		return <div class="mismatch"><b>client</b></div>;
		#else
		return <div class="mismatch"><i>server</i></div>;
		#end
	}

	public static final Mismatch = Island.define("mismatch", MismatchView, {script: "islands.js", load: Eager});

	// JavaScript calling WebAssembly: lab.wasm's LabExports, bytes in bulk
	static function LabView(props:{wasm:String}):View {
		var out = signal("loading " + props.wasm);
		onMount(() -> {
			#if js
			WasmModule.load(props.wasm, {imports: ["web/imports.mjs"]}).then(m -> {
				LabExports.module = m;
				var bytes = haxe.io.Bytes.alloc(1 << 16);
				for (i in 0...bytes.length)
					bytes.set(i, i & 255);
				var inv = LabExports.invert(bytes);
				var ok = inv.length == bytes.length;
				for (i in 0...bytes.length)
					if (inv.get(i) != 255 - (i & 255)) ok = false;
				out.value = [
					"sum " + LabExports.sum(2, 3),
					"invert " + (ok ? "ok" : "wrong") + " " + inv.length,
					"greet " + LabExports.greet("page"),
					"half " + LabExports.half(5),
					"even " + LabExports.even(4) + " " + LabExports.even(3)
				].join("; ");
			}, e -> out.value = "failed: " + e);
			#end
		});
		return <p class="lab">{out}</p>;
	}

	public static final Lab = Island.define("lab", LabView, {script: "islands.js", load: Idle});
}
