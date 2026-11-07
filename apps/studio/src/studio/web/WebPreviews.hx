package studio.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.Json;
import helder.async.*;
import helder.compiler.service.Diagnostic;
import helder.compiler.service.LiteralEdit;
import helder.image.Image;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import hxmc.unsafe.*;
import studio.Previews.Screen;
import studio.Project;
import studio.web.StudioWeb.WebText;

using StringTools;

// The studio's previews in the browser (studio.Previews there): one
// preview host for the whole project (helder.story.web.Preview: the
// project's program, a dev build for the web, run once in a Web Worker
// with every story mounted as a root of its own), not a process a screen.
// The page starts it (studio.mjs: StudioWeb.preview_start) and relays both
// ways: the devtools protocol's lines (each request naming its screen) and
// each frame, an ImageBitmap the worker drew on its OffscreenCanvas, which
// becomes the screen's image (a browser image's handle: the studio's
// renderer uploads it, copyExternalImageToTexture, and draws it as any
// other). Only the screens in view draw (show: the canvas' camera's), the
// screen zoomed into every frame. A live literal's edit is patched in the
// program (Hot.literals, against the tables the preview was built with:
// LiteralEdit), nothing built; a structural edit needs the compiler in its
// worker (helder.compiler.service as wasm), else it is saved and said.
class WebPreviews {
	public final project:Project;
	public final screens:Array<Screen>;
	public final status = signal("starting");
	public final diagnostics:Signal<Array<Diagnostic>> = signal([]);
	public final buildMs = signal(0);
	public var onFrame:Null<Screen->Void> = null;
	public var onLog:String->Void = s -> Sys.println(s);
	public var failed(default, null) = false;
	// the host's screens by index (Host.ready's order)
	var order:Array<Screen> = [];
	var running = false;
	var stopping = false;
	// the screens in view and the one focused, last told
	var shown = "";
	// (the last show asked: told again to a host once it is ready, a new build's too)
	var showWanted:Null<{names:Array<String>, focused:Null<String>, scale:Float}> = null;
	final pending = new Map<Int, Dynamic->Void>();
	var nextId = 1;
	// the live literals' tables the preview was built with, by the project's path; the patches sent since
	final built = new Map<String, {content:String, entries:Array<helder.markup.Live.Entry>}>();
	final sent = new Map<String, String>();
	// the program's start (ms), from the page's start event
	public var startMs(default, null) = -1.0;

	public function new(project:Project) {
		this.project = project;
		screens = [for (s in project.screens) new Screen(s)];
		for (t in project.tables)
			built.set(project.real(t.file), {content: t.content, entries: t.entries});
	}

	public function screen(name:String):Null<Screen>
		return Lambda.find(screens, s -> s.info.name == name);

	public function allShown():Bool
		return !Lambda.exists(screens, s -> s.version == 0 && !s.crashed) || failed;

	public function busy():Bool
		return !failed && !allShown();

	// the worker started (its module the page's), its events relayed
	@:coroutine public function start(task:Node) {
		if (StudioWeb.preview_start(0) == 0) {
			fail("no preview module for this project (the compiler's worker builds one once it is there)");
			return;
		}
		running = true;
		setStatus("running");
		task.async(_ -> while (!stopping) {
			poll();
			Async.delay(0.004);
		});
	}

	function setStatus(s:String) {
		failed = s == "failed";
		status(s);
	}

	function fail(why:String) {
		setStatus("failed");
		onLog('studio: $why');
	}

	// the page's events: lines, frames, logs
	function poll() {
		Arena.scoped(a -> {
			var ev:Ptr<Int32> = a.alloc(32);
			var kind;
			while ((kind = StudioWeb.preview_next(ev)) != 0) switch kind {
				case 1:
					line(WebText.take(ev[0]));
				case 2:
					frame(ev[0], ev[1], ev[2], ev[3], ev[4]);
				case 3:
					onLog('[preview] ' + WebText.take(ev[0]));
				case 4:
					running = false;
					for (s in screens)
						s.crashed = true;
					onLog('studio: the preview ended (exit code ${ev[0]})');
					if (onFrame != null) onFrame(screens[0]);
				case 5:
					startMs = ev[0];
				case 6:
					compiled.set(ev[0], Json.parse(WebText.take(ev[1])));
				case _:
			}
		});
	}

	function line(text:String) {
		var m:Dynamic = try Json.parse(text) catch (_:Dynamic) null;
		if (m == null) return;
		if (m.method == null) {
			var id = Std.int(m.id);
			var f = pending.get(id);
			if (f != null) {
				pending.remove(id);
				f(m);
			}
			return;
		}
		switch (m.method : String) {
			case "Host.ready":
				var list:Array<Dynamic> = m.params.screens;
				order = [for (x in list) screen(x.name)];
				if (showWanted != null) send("Host.show", {screens: showWanted.names, focused: showWanted.focused, scale: showWanted.scale}, null);
			case "Hot.patched":
				for (s in screens)
					s.patchedMs = m.params.ms;
			case _:
		}
	}

	// a frame: its bitmap the screen's image (replaced in place: the renderer uploads it again)
	function frame(index:Int, handle:Int, width:Int, height:Int, version:Int) {
		var s = order[index];
		if (s == null) {
			StudioWeb.frame_release(handle);
			return;
		}
		var img = Image.ofBrowser(handle, width, height, true);
		var first = s.version == 0;
		var now = s.image.peek();
		if (now == null) s.image(img) else {
			var old = now.browser;
			now.replace(img);
			if (old != 0) StudioWeb.frame_release(old);
		}
		s.version++;
		s.frames(s.version);
		s.reloading = false;
		if (s.crashed) s.crashed = false;
		if (first) s.shownAt = haxe.Timer.stamp();
		if (onFrame != null) onFrame(s);
	}

	// the screens in view (the others suspended in the host, their last
	// frames kept) and the one zoomed into, drawn at scale pixels a point
	// (the canvas' zoom: its frames as sharp as the studio shows them)
	public function show(names:Array<String>, focused:Null<String>, scale = 1.0) {
		var key = names.join("\n") + "\t" + (focused ?? "") + "\t" + scale;
		if (key == shown) return;
		shown = key;
		showWanted = {names: names, focused: focused, scale: scale};
		if (order.length > 0) send("Host.show", {screens: names, focused: focused, scale: scale}, null);
	}

	function send(method:String, params:Dynamic, done:Null<Dynamic->Void>) {
		var id = nextId++;
		if (done != null) pending.set(id, done);
		var l = Json.stringify({jsonrpc: "2.0", id: id, method: method, params: params});
		Arena.scoped(a -> StudioWeb.preview_send(a.cstring(l)));
	}

	// a file written (the page keeps it in OPFS)
	public function write(path:String, text:String)
		studio.Files.save(path, text);

	// a save from the code view: its live literals patched, else a build's (the compiler's worker)
	@:coroutine public function saved(task:Node, file:String, ?literalsOnly:Bool):String {
		var why = null;
		var patches = literalPatches(file, studio.Files.read(file), w -> why = w);
		if (patches != null && patches.length == 0) return "unchanged";
		if (patches != null && patch(patches)) {
			took(patches);
			return "patched";
		}
		if (literalsOnly == true) return "failed";
		onLog('studio: a build: ${haxe.io.Path.withoutDirectory(file)}: ${why ?? "a literal read once, not bound"}');
		return rebuild(task, [file]) ? "built" : "failed";
	}

	// the patches of a file's text (null: a build's, why said; empty: none changed)
	public function literalPatches(file:String, text:String, ?why:String->Void):Null<Array<{id:String, source:String}>> {
		var b = built.get(file);
		if (b == null) {
			if (why != null) why("no live literals known");
			return null;
		}
		var d = LiteralEdit.diff(b.content, text, b.entries, why);
		if (d == null) return null;
		var out = [], changed = new Map<String, String>();
		for (c in d)
			changed.set(c.id, c.source);
		for (e in b.entries) {
			var was = sent.get(e.id) ?? b.content.substring(e.start, e.end);
			var is = changed.get(e.id) ?? b.content.substring(e.start, e.end);
			if (was != is) out.push({id: e.id, source: is});
		}
		return out;
	}

	public function took(list:Array<{id:String, source:String}>)
		for (c in list)
			sent.set(c.id, c.source);

	// live literals sent to the program (one program: every screen's next frame shows them)
	public function patch(list:Array<{id:String, source:String}>):Bool {
		if (!running) return false;
		for (s in screens)
			s.patchedMs = -1;
		send("Hot.literals", {set: list}, r -> {
			var stale:Array<String> = r.result?.stale ?? [];
			if (stale.length > 0) onLog('studio: ${stale.length} literal(s) read once: ${stale.join(", ")}');
		});
		return true;
	}

	// a structural edit: built by the compiler's worker (helder.compiler.web,
	// when the page has one: its protocol's build, the screens' program
	// written beside the project as a cold build's is, its story files
	// copied in as modules), the host started again from its state; without
	// that worker: saved, not built
	@:coroutine public function rebuild(task:Node, changed:Array<String>):Bool {
		diagnostics([]);
		var gen = '${project.dir}/.studio/gen';
		var modules = [];
		for (f in [for (s in project.screens) s.file]) {
			var m = haxe.io.Path.withoutDirectory(f);
			if (!m.endsWith(".story.hx") || modules.contains(m.substr(0, m.length - 9) + "_story")) continue;
			m = m.substr(0, m.length - 9) + "_story";
			modules.push(m);
			studio.Files.save('$gen/$m.hx', studio.Files.read(f));
			// (the compiler's path of it: /work/<name>/...)
			project.links.set("/work" + '$gen/$m.hx'.substr(gen.indexOf("/", 1)), f);
		}
		if (modules.length == 0) {
			onLog("studio: a structural edit of a TypeScript project needs its build in the browser (not yet): saved, not built");
			return false;
		}
		var all = [for (m in modules) 'helder.story.Stories.of("$m")'].join(".concat(") + [for (_ in 1...modules.length) ")"].join("");
		studio.Files.save('$gen/StudioScreens.hx', 'class StudioScreens {\n\tstatic function main()\n\t\thelder.story.Screens.run($all);\n}\n');
		var request = Json.stringify({entry: '$gen/StudioScreens.hx', args: ["-cp", project.dir, "-D", 'helder.name=${project.name}']});
		var id = Arena.scopedValue(a -> StudioWeb.compile(a.cstring(request)));
		if (id == 0) {
			onLog("studio: a structural edit needs the compiler's worker (helder.compiler.web): saved, not built");
			return false;
		}
		setStatus("building");
		var t0 = haxe.Timer.stamp();
		while (!compiled.exists(id) && haxe.Timer.stamp() - t0 < 300)
			Async.delay(0.01);
		var r:Dynamic = compiled.get(id);
		compiled.remove(id);
		buildMs(Math.round((haxe.Timer.stamp() - t0) * 1000));
		helder.view.graph.Graph.flush();
		var ds:Array<Diagnostic> = r == null || r.diagnostics == null ? [] : r.diagnostics;
		diagnostics([for (d in ds) d.file == null ? d : {file: project.real(d.file), line: d.line, column: d.column, endColumn: d.endColumn, severity: d.severity, message: d.message}]);
		if (r == null || r.ok != true) {
			setStatus("failed");
			onLog('studio: the build failed: ' + (r?.why ?? r?.messages ?? "no answer"));
			return false;
		}
		// (the build's paths: the compiler's, /work/<name>/..., for each of the project's files)
		for (f in project.sources()) {
			for (k in [for (k => v in project.links) if (v == f) k])
				project.links.remove(k);
			project.links.set("/work" + f.substr(f.indexOf("/", 1)), f);
		}
		// (the build's live literals' tables: those of the files' contents now, the others the last build's no longer)
		for (f in changed)
			built.remove(f);
		var tables:Array<Dynamic> = r.tables ?? [];
		for (t in tables) {
			var file = project.real(t.file);
			var text = try studio.Files.read(file) catch (_:Dynamic) null;
			if (text != null && haxe.crypto.Md5.encode(text) == t.name) {
				built.set(file, {content: text, entries: t.entries});
				for (e in (t.entries : Array<helder.markup.Live.Entry>))
					sent.remove(e.id);
			}
		}
		for (s in screens)
			s.reloading = true;
		setStatus("running");
		return true;
	}

	// the compiler's answers by request (StudioWeb.compile's ids)
	final compiled = new Map<Int, Dynamic>();

	// a devtools request about a screen (false: the host is not running)
	public function request(s:Screen, method:String, params:Dynamic, done:Dynamic->Void):Bool {
		if (!running) return false;
		var p:Dynamic = Reflect.copy(params) ?? {};
		p.screen = s.info.name;
		send(method, p, done);
		return true;
	}

	@:coroutine public function check():{ok:Bool, diagnostics:Array<Diagnostic>, ms:Int}
		return {ok: true, diagnostics: [], ms: 0};

	@:coroutine public function stop()
		stopping = true;
}
#end
