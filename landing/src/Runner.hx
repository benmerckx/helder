import Compiler;
import js.Browser.document;
import js.Browser.window;
import js.Syntax;
import js.html.Element;
import js.lib.Promise;
import js.lib.Uint8Array;

private typedef Instance = {host:Dynamic, reloadFn:Int, snapshot:Null<String>};

// A program on the stage: run by @hxmc/os's browser.mjs with its packages'
// imports, and swapped for a new build in place (live reload), as hxmc dev's
// page does it (docs/dev.md): the running build is asked for its snapshot
// (Hot's state: signals, Hot.keep), disposed (what it registered dropped,
// its GPU objects released), and the new one starts from the snapshot
// against the same canvas and GPU device. The builds are -D hxmc.dev ones:
// they take the imports of hxmc_dev. Not browser.mjs's track option: it
// records every element the page makes while a program runs (the editor's
// too) and removes them with it; the packages' own disposals (os's frames,
// listeners and audio, gfx's GPU objects) are what a swap needs.
class Runner {
	public var stdout:String->Void = _ -> {};
	public var stderr:String->Void = _ -> {};
	public var running(get, never):Bool;

	final screen:Element;
	var current:Null<Instance>;
	var gpu:Dynamic;
	var canvas:Null<Element>;
	// (a stop or a new run while one starts: the older one's result is dropped)
	var generation = 0;
	var browser:Null<Promise<Dynamic>>;

	public function new(screen:Element)
		this.screen = screen;

	function get_running()
		return current != null;

	function module():Promise<Dynamic>
		return browser ??= Syntax.code("import({0})", new js.html.URL("os/browser.mjs", document.baseURI).href);

	// stops the program and lets go of its canvas
	public function stop() {
		generation++;
		if (current != null) {
			try {
				current.host.dispose();
				current.host.os?.stop();
			} catch (_:Dynamic) {}
		}
		current = null;
		gpu = null;
		canvas = null;
		screen.innerHTML = "";
	}

	// a cold start of e's build on a new canvas (none for a sound)
	public function start(e:Example, bytes:Uint8Array, assets:Array<Array<Dynamic>>):Promise<Bool> {
		stop();
		if (e.demo.canvas != null) {
			var c = document.createCanvasElement();
			c.width = e.demo.canvas[0];
			c.height = e.demo.canvas[1];
			c.tabIndex = 0;
			screen.append(c);
			canvas = c;
		}
		return launch(e, bytes, assets, null);
	}

	// the new build in place of the running one, from its snapshot
	public function swap(e:Example, bytes:Uint8Array, assets:Array<Array<Dynamic>>):Promise<Bool> {
		var old = current;
		if (old == null) return start(e, bytes, assets);
		var snapshot:Null<String> = null;
		try {
			old.host.swapping = true;
			if (old.reloadFn != 0) old.host.call(old.reloadFn);
			snapshot = old.snapshot;
			old.host.dispose();
			var kept:Array<Element> = old.host.os?.canvases;
			if (kept != null && kept.length > 0) canvas = kept[0];
		} catch (err:Dynamic) {
			stderr("the running build could not hand over (" + Std.string(err) + "): a cold start");
			return start(e, bytes, assets);
		}
		current = null;
		return launch(e, bytes, assets, snapshot);
	}

	function launch(e:Example, bytes:Uint8Array, assets:Array<Array<Dynamic>>, snapshot:Null<String>):Promise<Bool> {
		var gen = ++generation;
		var restore = snapshot == null ? null : new js.html.TextEncoder().encode(snapshot);
		var state:Instance = {host: null, reloadFn: 0, snapshot: null};
		var dev = (h:Dynamic) -> {
			state.host = h;
			return {
				hxmc_dev: {
					restore_length: () -> restore == null ? -1 : restore.length,
					restore_take: (p:Int) -> (h.bytes(p, restore.length) : Uint8Array).set(restore),
					register: (f:Int) -> state.reloadFn = f,
					send: (p:Int, n:Int) -> state.snapshot = new js.html.TextDecoder().decode((h.bytes(p, n) : Uint8Array).slice()),
					frame: () -> {},
				}
			};
		}
		var base = document.baseURI;
		var imports:Array<Dynamic> = [for (i in e.imports) new js.html.URL(i, base).href];
		imports.push(dev);
		var files:haxe.DynamicAccess<String> = {};
		for (a in assets) files[a[0]] = js.html.URL.createObjectURL(new js.html.Blob([a[1]]));
		var fonts = e.fonts ? [for (f in ["fonts/DejaVuSans.ttf", "fonts/DejaVuSans-Bold.ttf"]) new js.html.URL(f, base).href] : [];
		return module().then(m -> m.run(bytes, {
			imports: imports, canvas: canvas, gpu: gpu, fonts: fonts, files: files, track: false, antialias: true, touchAction: "none",
			stdout: (l:String) -> if (gen == generation) stdout(l),
			stderr: (l:String) -> if (gen == generation) stderr(l),
			onError: (err:Dynamic) -> if (gen == generation) stderr(Std.string(err?.message ?? err)),
		})).then((r:Dynamic) -> {
			if (gen != generation) {
				try r.host.dispose() catch (_:Dynamic) {}
				return false;
			}
			current = state;
			var g:Dynamic = r.host.gfx;
			if (gpu == null && g != null && g.device != null) gpu = {adapter: g.adapter, device: g.device};
			if (r.exitCode != 0) stderr('exited with code ${r.exitCode}');
			return true;
		}, (err:Dynamic) -> {
			if (gen == generation) stderr(Std.string(err?.message ?? err));
			return false;
		});
	}

	public function focus()
		if (canvas != null) (cast canvas).focus({preventScroll: true});
}
