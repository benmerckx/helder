import Compiler;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.lib.Uint8Array;

// widgets.html (widgets.js): every widget of @hxmc/ui, twice, a switch
// between them: drawn on the GPU (GPU: landing/widgets/WidgetsPage.hx built
// ahead for wasm32-wasi, widgets.wasm, run by @hxmc/os's browser.mjs as a
// world's program is: Runner, WebGL2 where WebGPU fails) and as the DOM's
// elements under the theme's CSS (DOM, #dom: the same page compiled to
// JavaScript with hxmc.web's renderer, widgets-dom.js). Each loads the first
// time it is shown.
class WidgetsMain {
	static inline function byId(id:String):Element
		return document.getElementById(id);

	static var gpu:Null<js.lib.Promise<Bool>>;
	static var dom:Null<js.lib.Promise<Bool>>;
	static var runner:Runner;

	static function main() {
		runner = new Runner(byId("wp-screen"));
		runner.stderr = l -> js.Browser.console.error(l);
		runner.notice = l -> js.Browser.console.info(l);
		runner.onFail = fail;
		for (b in document.querySelectorAll(".mode button")) {
			var el:Element = cast b;
			el.onclick = () -> {
				window.history.replaceState(null, "", el.dataset.mode == "dom" ? "#dom" : window.location.pathname);
				show(el.dataset.mode);
			}
		}
		byId("wp-retry").onclick = () -> window.location.reload();
		show(window.location.hash == "#dom" ? "dom" : "gpu");
	}

	static function fail(why:String) {
		byId("wp-loading").hidden = true;
		byId("wp-failed-why").textContent = why;
		byId("wp-failed").hidden = false;
	}

	// one renderer shown, the other hidden (the drawn one's frames pause out of view); each loaded the first time
	static function show(mode:String) {
		for (b in document.querySelectorAll(".mode button")) {
			var el:Element = cast b;
			el.setAttribute("aria-pressed", Std.string(el.dataset.mode == mode));
		}
		byId("wp-screen").hidden = mode != "gpu";
		byId("wp-dom").hidden = mode != "dom";
		byId("wp-failed").hidden = true;
		var ready = mode == "gpu" ? (gpu ??= startGpu()) : (dom ??= startDom());
		byId("wp-loading").hidden = false;
		byId("wp-loading-what").textContent = mode == "gpu" ? "downloading the program" : "loading the DOM's widgets";
		ready.then(ok -> if (ok && byId(mode == "gpu" ? "wp-screen" : "wp-dom").hidden == false) byId("wp-loading").hidden = true);
	}

	// the DOM's widgets: the same page compiled to JavaScript (widgets-dom.js), the theme's CSS scoped to .hxmc
	static function startDom():js.lib.Promise<Bool> {
		var css = document.createLinkElement();
		css.rel = "stylesheet";
		css.href = "shadcn.css";
		document.head.append(css);
		return new js.lib.Promise((ok, _) -> {
			var s = document.createScriptElement();
			s.src = "widgets-dom.js";
			s.onload = () -> ok(true);
			s.onerror = () -> {
				fail("widgets-dom.js did not load");
				ok(false);
			}
			document.body.append(s);
		});
	}

	static function startGpu():js.lib.Promise<Bool> {
		var program:Example = {
			id: "widgets", pkg: "ui", main: "WidgetsPage", title: "Widgets", summary: "", tags: [], demo: {canvas: [1024, 768]},
			source: "", sources: [], args: [], imports: ["os/imports.mjs", "gfx/imports.mjs", "text/imports.mjs", "ui/imports.mjs"], fonts: true,
		};
		var bar = byId("wp-bar");
		return window.fetch("widgets.wasm").then(r -> {
			if (!r.ok) throw 'widgets.wasm: ${r.status}';
			// (the module's size, which Build writes on the page: Content-Length is the compressed one)
			var size = Std.parseInt(document.body.dataset.size ?? "") ?? 0;
			var reader = (cast r).body.getReader(), chunks:Array<Uint8Array> = [], loaded = 0;
			function next():js.lib.Promise<Uint8Array> {
				return reader.read().then(c -> {
					if (c.done) {
						var b = new Uint8Array(loaded), at = 0;
						for (x in chunks) {
							b.set(x, at);
							at += x.length;
						}
						return js.lib.Promise.resolve(b);
					}
					chunks.push(c.value);
					loaded += c.value.length;
					if (size > 0) bar.style.width = '${Math.min(100, loaded / size * 100)}%';
					return next();
				});
			}
			return next();
		}).then(bytes -> {
			byId("wp-loading-what").textContent = "starting";
			return runner.start(program, bytes, []);
		}).then(started -> {
			if (started) runner.focus();
			return started;
		}, err -> {
			fail(Fail.describe(err));
			return false;
		});
	}
}
