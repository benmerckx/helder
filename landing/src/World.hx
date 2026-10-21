import Compiler;
import Protocol;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.lib.Promise;

// A world: an example compiled in this tab and running on the stage, its
// source in the editor, live. Every edit is kept (Store: IndexedDB) and,
// once typing pauses, built by the resident compiler and swapped in with
// the program's state (Runner); a build with errors leaves the last good
// one running and shows its errors in the editor. The dock: restart (a
// cold start), the code, the native download (the same source, edits
// included, for any target).
class World {
	public var current(default, null):Null<Example>;

	final client:CompilerClient;
	final sky:Sky;
	final forge:Forge;
	final runner:Runner;
	final universe:Universe;
	final manifest:Manifest;
	var editor:Null<Editor>;
	// the open world's files: as shipped, and as they are now
	final originals = new Map<String, String>();
	final texts = new Map<String, String>();
	var files:Array<String> = [];
	var active = "";
	var lastGood:Null<Reply>;
	var buildTimer = -1;
	var saveTimer = -1;
	var generation = 0;
	var srcPack:Null<Promise<Map<String, js.lib.Uint8Array>>>;

	public function new(manifest:Manifest, client:CompilerClient, sky:Sky, forge:Forge, universe:Universe) {
		this.manifest = manifest;
		this.client = client;
		this.sky = sky;
		this.forge = forge;
		this.universe = universe;
		runner = new Runner(byId("screen"));
		runner.stdout = l -> log(l);
		runner.stderr = l -> log(l, "err");
		runner.notice = l -> log(l);
		client.onProgress = (what, loaded, total) -> if (!byId("forge").hidden) forge.progress(what, loaded, total);
		client.onFiles = f -> if (!byId("forge").hidden) forge.files(f) else sky.kick(0.004 * f.length);
		wire();
	}

	static inline function byId(id:String):Element
		return document.getElementById(id);

	// ---- entering and leaving ----

	public function enter(e:Example) {
		var gen = ++generation;
		current = e;
		lastGood = null;
		sky.kick(1.2);
		var world = byId("world");
		world.className = 'view pkg-${e.pkg}';
		world.style.setProperty("--c1", Universe.COLORS[e.pkg]);
		byId("universe").hidden = true;
		world.hidden = false;
		byId("world-title").textContent = e.title;
		byId("world-summary").textContent = e.summary;
		byId("world-pkg").textContent = '@hxmc/${e.pkg}';
		var size = e.demo.canvas ?? [16, 9];
		world.style.setProperty("--aspect", '${size[0] / size[1]}');
		byId("console").innerHTML = "";
		setStatus("idle", "");
		code(false);
		runner.stop();
		editor?.reset();
		visit(e);
		files = [e.source].concat(e.sources);
		active = e.source;
		originals.clear();
		texts.clear();
		// the shipped sources and the visitor's edits, then the first build
		Promise.all([for (p in files) sourceOf(p).then(t -> originals.set(p, t))]).then(_ -> Store.edits(files)).then(edits -> {
			if (gen != generation) return;
			for (p in files) texts.set(p, edits.exists(p) ? edits[p] : originals[p]);
			tabs();
			if (Lambda.count(edits) > 0) Main.toast('✎ <b>Your edits are back</b> · ${[for (p in edits.keys()) p.split("/").pop()].join(", ")}');
			if (e.demo.sound != null) {
				var play = byId("play");
				play.hidden = false;
				play.querySelector("span").textContent = "Tap to compile and play";
			} else {
				byId("play").hidden = true;
				first();
			}
		});
	}

	public function leave() {
		generation++;
		window.clearTimeout(buildTimer);
		runner.stop();
		code(false);
		current = null;
		byId("world").hidden = true;
		byId("universe").hidden = false;
		sky.calm = false;
		sky.kick(0.8);
	}

	function visit(e:Example) {
		var p = Store.progress;
		if (p.visited.contains(e.id)) return;
		p.visited.push(e.id);
		Store.keep();
		universe.visited(e.id);
		universe.hud();
		if (p.visited.length == 1) haxe.Timer.delay(() -> Main.toast("🪐 <b>First world</b> · compiled right here, in this tab"), 900);
		else if (p.visited.length == manifest.examples.length) haxe.Timer.delay(() -> Main.toast("🌌 <b>Every world visited</b> · the whole universe, from source"), 900);
	}

	// the source of a file as shipped: src.pack (the worker fetched it too: the HTTP cache)
	function sourceOf(path:String):Promise<String> {
		if (srcPack == null) srcPack = js.Browser.window.fetch("src.pack").then(r -> r.arrayBuffer()).then(b -> {
			var m = new Map<String, js.lib.Uint8Array>();
			for (f in Pack.unpack(new js.lib.Uint8Array(b))) m.set(f.path, f.data);
			m;
		});
		return srcPack.then(m -> new js.html.TextDecoder().decode(m[path]));
	}

	// the files edited, as the worker takes them
	function edits():Edits {
		var out = new Edits();
		for (p in files) if (texts[p] != originals[p]) out[p] = texts[p];
		return out;
	}

	// ---- builds ----

	// the first build: the forge over the stage, then a cold start
	function first():Void {
		var e = current, gen = generation;
		byId("run").setAttribute("disabled", "");
		sky.calm = false;
		forge.show(client.state == "ready" ? "warming up" : "downloading the compiler", Store.progress.counts[e.id]);
		client.build(e, "wasm32-wasi", true, edits()).then(r -> {
			if (gen != generation || r == null) return null;
			byId("run").removeAttribute("disabled");
			byId("console").innerHTML = "";
			if (!r.ok) {
				forge.hide();
				failed(r);
				return null;
			}
			Store.progress.counts[e.id] = forge.reads;
			Store.keep();
			forge.done(r.ms / 1000);
			log('compiled ${e.main}.hx → ${Math.round(r.bytes.length / 1024)} KB of wasm in ${Math.round(r.ms / 10) / 100} s, in this tab · edit the code: it reloads live', "ok");
			setStatus("live", '${Math.round(r.ms / 10) / 100}s');
			lastGood = r;
			return new Promise((ok, _) -> haxe.Timer.delay(() -> ok(r), 380));
		}).then(r -> {
			if (r == null || gen != generation) return;
			forge.hide();
			sky.kick(0.6);
			runner.start(e, r.bytes, r.assets).then(started -> if (started) {
				sky.calm = true;
				runner.focus();
			});
		}, err -> {
			forge.hide();
			byId("run").removeAttribute("disabled");
			log(Fail.describe(err), "err");
		});
	}

	// an edit: kept, and built once typing pauses
	function edited(text:String) {
		texts[active] = text;
		tabs();
		var path = active;
		window.clearTimeout(saveTimer);
		saveTimer = window.setTimeout(() -> text == originals[path] ? Store.forget(path) : Store.save(path, text), 300);
		window.clearTimeout(buildTimer);
		buildTimer = window.setTimeout(live, 300);
		setStatus("pending", "");
	}

	// a live build, swapped in
	function live() {
		var e = current, gen = generation;
		if (e == null) return;
		setStatus("building", "");
		client.build(e, "wasm32-wasi", true, edits()).then(r -> {
			if (r == null || gen != generation) return;
			editor?.diagnostics(r.messages);
			if (!r.ok) {
				failed(r);
				return;
			}
			lastGood = r;
			setStatus("live", '${Math.round(r.ms / 10) / 100}s');
			if (e.demo.sound != null && !runner.running) return;
			sky.kick(0.25);
			flash();
			runner.swap(e, r.bytes, r.assets).then(_ -> sky.calm = true);
		}, err -> setStatus("error", Fail.describe(err)));
	}

	function failed(r:Reply):Void {
		editor?.diagnostics(r.messages);
		var errors = r.messages.filter(m -> !m.warning);
		setStatus("error", '${errors.length} error${errors.length == 1 ? "" : "s"}${runner.running ? " · last good build runs" : ""}');
		var shown = 0;
		for (m in errors) if (shown++ < 6) log('${m.file.substr(m.file.lastIndexOf("/") + 1)}:${m.line}: ${m.text}', "err", m);
		if (errors.length == 0) for (l in r.log.slice(0, 8)) log(l, "err");
	}

	// a cold start of the last good build (state dropped)
	function restart() {
		var e = current;
		if (e == null) return;
		byId("play").hidden = true;
		if (lastGood == null) {
			first();
			return;
		}
		sky.kick(0.5);
		runner.start(e, lastGood.bytes, lastGood.assets).then(_ -> sky.calm = true);
	}

	function flash() {
		var s = byId("stage");
		s.classList.remove("reloaded");
		untyped s.offsetWidth;
		s.classList.add("reloaded");
	}

	function setStatus(state:String, text:String):Void {
		var el = byId("live");
		el.dataset.state = state;
		el.querySelector("span").textContent = switch state {
			case "live": 'live · $text';
			case "building": "building…";
			case "pending": "editing…";
			case "error": text;
			case _: "";
		}
	}

	// ---- the console ----

	function log(text:String, ?cls:String, ?m:Message):Void {
		var c = byId("console");
		var d = document.createDivElement();
		if (cls != null) d.className = cls;
		if (m != null && files.contains(m.file.substr("/lib/src/".length))) {
			var a = document.createAnchorElement();
			a.textContent = text;
			a.onclick = () -> {
				code(true);
				show(m.file.substr("/lib/src/".length));
				editor.goto(m.line, m.lines ? 0 : m.from);
			}
			d.append(a);
		} else d.textContent = text;
		c.append(d);
		while (c.children.length > 200) c.firstElementChild.remove();
		c.scrollTop = c.scrollHeight;
	}

	// ---- the code ----

	function code(open:Bool) {
		var world = byId("world");
		world.classList.toggle("coding", open);
		byId("show-source").setAttribute("aria-expanded", Std.string(open));
		byId("source").hidden = !open;
		for (b in document.querySelectorAll(".mode button")) {
			var el:Element = cast b;
			el.setAttribute("aria-pressed", Std.string((el.dataset.mode == "code") == open));
		}
		if (!open || current == null || texts.get(active) == null) return;
		var e = current;
		loadEditor().then(_ -> {
			if (editor == null) {
				editor = new Editor(byId("editor"), byId("info"));
				editor.onChange = edited;
				editor.minimap(cast byId("minimap"));
				editor.onLayout = corner;
				editor.lsp = {
					complete: (offset, explicit) -> display("display/completion", offset, {wasAutoTriggered: !explicit}),
					hover: offset -> display("display/hover", offset),
					signature: offset -> display("display/signatureHelp", offset, {wasAutoTriggered: true}),
				};
			}
			if (current == e && !byId("source").hidden) show(active);
			corner();
		}, err -> log("the editor did not load: " + Fail.describe(err), "err"));
	}

	// editor.js (CodeMirror, the global CM), the first time the code opens
	static var editorScript:Null<Promise<Bool>>;

	static function loadEditor():Promise<Bool> {
		return editorScript ??= new Promise((ok, fail) -> {
			var s = document.createScriptElement();
			s.src = "editor.js";
			s.onload = () -> ok(true);
			s.onerror = () -> {
				editorScript = null;
				fail("editor.js");
			}
			document.head.append(s);
		});
	}

	// the corner (a phone's): just above the info bar and the key bar
	function corner() {
		var world = byId("world"), info = byId("info");
		if (!world.classList.contains("coding") || info.offsetParent == null) return;
		var bottom = world.getBoundingClientRect().bottom - info.getBoundingClientRect().top + 10;
		world.style.setProperty("--corner-bottom", '${bottom}px');
		editor?.drawMap();
	}

	function setCorner(which:String) {
		byId("world").classList.toggle("corner-map", which == "map");
		for (b in byId("corner").querySelectorAll("button")) {
			var el:Element = cast b;
			el.setAttribute("aria-selected", Std.string(el.dataset.corner == which));
		}
		editor?.drawMap();
	}

	function display(method:String, offset:Int, ?extra:Dynamic):Promise<Null<Dynamic>> {
		if (current == null || client.state != "ready") return Promise.resolve(null);
		return client.display(current, method, "/lib/src/" + active, offset, edits(), extra).catchError(_ -> null);
	}

	function show(path:String) {
		active = path;
		editor.open(path, texts[path]);
		tabs();
		if (lastGood != null) editor.diagnostics(lastGood.messages);
	}

	function tabs() {
		var t = byId("tabs");
		t.innerHTML = "";
		for (p in files) {
			var b = document.createButtonElement();
			b.type = "button";
			b.setAttribute("role", "tab");
			b.textContent = p.split("/").pop();
			b.setAttribute("aria-selected", Std.string(p == active));
			if (texts[p] != originals[p]) b.classList.add("edited");
			b.onclick = () -> show(p);
			t.append(b);
		}
		byId("reset").hidden = texts[active] == originals[active];
	}

	// ---- the download ----

	function download(target:String) {
		var e = current;
		if (e == null) return;
		if (Download.chosen.guessed) {
			Download.picker(true, manifest.targets, download);
			return;
		}
		var l = Download.LABELS[target];
		var btn = byId("download");
		btn.setAttribute("disabled", "");
		var playing = runner.running;
		forge.show('forging for ${l[0]} · ${l[1]}', Store.progress.counts['${e.id}@native']);
		forge.set("fetch", 'fetching the ${l[0]} runtime');
		client.build(e, target, false, edits()).then(r -> {
			btn.removeAttribute("disabled");
			forge.hide();
			if (r == null) return;
			if (!r.ok) {
				failed(r);
				return;
			}
			Store.progress.counts['${e.id}@native'] = forge.reads;
			log('compiled ${e.main}.hx for ${l[0]} ${l[1]} → ${Math.round(r.bytes.length / 1024)} KB in ${Math.round(r.ms / 10) / 100} s, in this tab', "ok");
			var name = Download.save(e, target, r.file, r.bytes, r.assets);
			var p = Store.progress;
			if (!p.native.contains(target)) {
				p.native.push(target);
				Main.toast('⚡ <b>Went native</b> · ${l[0]} ${l[1]}${p.native.length > 1 ? ' · ${p.native.length} targets' : ""}');
			}
			Store.keep();
			universe.hud();
			Download.howToRun(e, target, name);
			if (!playing && e.demo.sound == null && lastGood == null) first();
		}, err -> {
			btn.removeAttribute("disabled");
			forge.hide();
			log(Fail.describe(err), "err");
		});
	}

	// ---- wiring ----

	function wire() {
		byId("run").onclick = restart;
		byId("play").onclick = () -> {
			byId("play").hidden = true;
			lastGood == null ? first() : restart();
		};
		byId("show-source").onclick = () -> code(byId("source").hidden);
		byId("source-close").onclick = () -> code(false);
		for (b in document.querySelectorAll(".mode button")) {
			var el:Element = cast b;
			el.onclick = () -> code(el.dataset.mode == "code");
		}
		// (the stage in its corner while coding on a phone: back to playing)
		byId("stage").addEventListener("click", () -> if (byId("world").classList.contains("coding") && window.innerWidth <= 760) code(false));
		for (b in byId("corner").querySelectorAll("button")) {
			var el:Element = cast b;
			el.onclick = () -> setCorner(el.dataset.corner);
		}
		window.addEventListener("resize", corner);
		byId("reset").onclick = () -> if (editor != null && originals.exists(active)) editor.replace(originals[active]);
		byId("download").onclick = () -> download(Download.chosen.target);
		byId("pick").onclick = () -> Download.picker(byId("targets").hidden, manifest.targets, download);
		byId("targets").addEventListener("keydown", (ev:js.html.KeyboardEvent) -> {
			var items = [for (c in byId("targets").children) c];
			var i = items.indexOf(cast document.activeElement);
			switch ev.key {
				case "ArrowDown": items[(i + 1) % items.length].focus();
				case "ArrowUp": items[(i - 1 + items.length) % items.length].focus();
				case "Enter" | " ": document.activeElement.click();
				case "Escape":
					Download.picker(false, manifest.targets, download);
					byId("pick").focus();
				case _: return;
			}
			ev.preventDefault();
		});
		window.addEventListener("click", (ev:js.html.Event) -> {
			if (!byId("targets").hidden && (cast ev.target).closest(".split") == null) Download.picker(false, manifest.targets, download);
		});
	}

	// Escape: the topmost thing closes; false when nothing was open
	public function escape():Bool {
		if (!byId("sheet").hidden) byId("sheet").hidden = true;
		else if (!byId("targets").hidden) Download.picker(false, manifest.targets, download);
		else if (!byId("source").hidden) code(false);
		else return false;
		return true;
	}
}
