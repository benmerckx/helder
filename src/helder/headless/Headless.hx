package helder.headless;

import haxe.io.Bytes;
import helder.headless.Inspector;
import helder.headless.Script;
import helder.os.Event;
import helder.os.Surface;
import helder.os.headless.HeadlessWindow;

using StringTools;

// A headless run of a program (`helder run --headless`, src/helder/cli:
// a build with -D helder.headless, its options in HELDER_HEADLESS as
// JSON): its windows are HeadlessWindows (helder.os.Window: offscreen
// surfaces, drawn by the real renderer), its loop (App.run) steps a
// virtual clock (Time: frame n at n / fps seconds, whatever the machine's
// speed) instead of waiting for the display, its events are the script's
// (Script: pointer moves and presses, keys, text, wheel, resizes, menus'
// and file dialogs' answers, aimed at a node by its tag or at x, y), and
// each frame gives the outputs asked for: PNG snapshots at a time, the
// node tree (Inspector: helder.ui's) as JSON, PNG sequences (and a
// video's frames, which the CLI encodes), the motion trace (JSON lines),
// keycaps and press ripples drawn over the frames (Overlay). Math.random
// is seeded (--seed), so the same script gives the same bytes.
//
// Holds (hold): a program that waits for work outside it (the studio: its
// builds, its preview processes' frames) holds the script while it does:
// the frames go on (each 1/fps later on the virtual clock, a few
// milliseconds apart on the machine's: its timers and I/O progress), the
// script's steps and the outputs' times wait, all moved by the time held.
//
// Serve (the option {"serve": {"frames": file}}: the studio's previews,
// helder.story.Screens): no script and no end, the virtual clock the
// machine's (60 frames a second, paced), each frame drawn written to the
// file (a header "HLDF", width, height, version as 32-bit little-endian
// integers, then its RGBA rows; written beside it and renamed over it) and
// told over the devtools connection in a dev build: the notification
// `Headless.frame {version, width, height, path}`.
class Headless {
	// a tap's press held (s)
	public static inline var HOLD = 0.05;

	public static var run(get, never):Headless;
	static var current:Null<Headless>;

	static function get_run():Headless {
		if (current == null) current = new Headless(Sys.getEnv("HELDER_HEADLESS") ?? "{}");
		return current;
	}

	// its options
	public final scale:Float;
	// --size in points (0: the program's)
	public final width:Int;
	public final height:Int;
	public final dark:Bool;
	public final reducedMotion:Bool;
	public final fps:Float;
	final script:Script;
	final snaps:Array<{path:String, at:Float, done:Bool}> = [];
	final trees:Array<{path:String, at:Float, done:Bool}> = [];
	// (a sequence's frames all of its first's size: a window resized during it cropped or padded, top left kept)
	final sequences:Array<{dir:String, start:Float, count:Int, every:Int, written:Int, width:Int, height:Int}> = [];
	final trace:Null<String>;
	// --stats: each frame's work (ms, from its events to its end) and what it
	// allocated (GC bytes, collections), its input events by kind, what it
	// recorded on the GPU (helder.gfx.FrameCounts: passes, draw calls, the
	// instances they drew, pipelines and textures set; the 2D renderer's
	// quads, its CPU ms from painting to its pass encoded and of that its
	// upload's and its draws' (the encoder's calls, the driver's work in
	// them), the bytes it uploaded, the GC bytes it allocated, painting
	// included; all 0 for a frame that drew nothing); written at the end, with a summary printed
	final stats:Null<String>;
	final statFrames:Array<Float> = [];
	var statStart = -1.0;
	var statBytes = 0.0;
	var statCollections = 0;
	var statKeys = 0;
	var statWheels = 0;
	var statPointers = 0;
	final overlay:Null<Overlay>;
	// when the run ends (s)
	final end:Float;
	// serve: the file each frame drawn is written to (null: a run)
	public final serve:Null<String>;
	var serveStart = 0.0;
	var served = 0;
	// holds: what the script and the outputs wait on, and the time they waited
	final holds:Array<{done:Void->Bool, why:String, until:Float, since:Float}> = [];
	var shift = 0.0;

	// the windows opened (the first one's pixels and nodes the outputs')
	final windows:Array<HeadlessWindow> = [];
	// what draws the first window's content (helder.ui's), when it tells
	public var inspector:Null<Inspector> = null;

	var frame = 0;
	var stepAt = 0;
	final acts:Array<Act> = [];
	final posted:Array<Event> = [];
	final answers:Array<Step> = [];
	// the pointer (points)
	var px = 0.0;
	var py = 0.0;
	var buttons = 0;
	// the first window's last frame (RGBA, rows top to bottom)
	var pixels:Null<Bytes> = null;
	var pixelsWidth = 0;
	var pixelsHeight = 0;
	final wantsPixels:Bool;
	final wantsNodes:Bool;
	// the nodes' last frame (moving: changed since)
	var last = new Map<Int, InspectedNode>();
	var traceOut:Null<sys.io.FileOutput> = null;
	var finished = false;
	final event = new Event();

	function new(json:String) {
		var o:Dynamic = try haxe.Json.parse(json) catch (e:Dynamic) fail('HELDER_HEADLESS is not JSON: $e');
		scale = num(o, "scale", 1);
		var size:Null<String> = Reflect.field(o, "size");
		if (size != null) {
			var wh = size.split("x");
			width = Std.parseInt(wh[0]) ?? 0;
			height = Std.parseInt(wh[1] ?? "") ?? 0;
			if (width <= 0 || height <= 0) fail('--size $size: WIDTHxHEIGHT in points');
		} else width = height = 0;
		if (scale <= 0) fail('--scale $scale: above 0');
		dark = Reflect.field(o, "theme") == "dark";
		reducedMotion = Reflect.field(o, "reducedMotion") == true;
		fps = num(o, "fps", 60);
		if (fps <= 0) fail('--fps $fps: above 0');
		var file:Null<String> = Reflect.field(o, "script");
		script = file == null ? new Script() : try Script.parse(sys.io.File.getContent(file), file) catch (e:String) fail(e);
		for (s in script.steps)
			if (s.type == "file-dialog" || s.type == "file-dialog-cancel") answers.push(s);
		var ends = [];
		for (s in (Reflect.field(o, "snaps") : Array<Dynamic>) ?? []) {
			var at = timeOf(s.at);
			snaps.push({path: s.path, at: at, done: false});
			ends.push(at);
		}
		for (s in (Reflect.field(o, "trees") : Array<Dynamic>) ?? []) {
			var at = timeOf(s.at);
			trees.push({path: s.path, at: at, done: false});
			ends.push(at);
		}
		for (s in (Reflect.field(o, "sequences") : Array<Dynamic>) ?? []) {
			var start = timeOf(s.start ?? "0");
			// (count frames; else duration seconds of them; else through the end: auto)
			var d:Dynamic = s.duration;
			var count:Int = s.count != null ? Std.int(s.count) : d != null && d != "auto" && d != "end" ? Std.int(Math.round(timeOf(d) * fps)) : Std.int(Math.round((autoEnd()
				- start) * fps)) + 1;
			if (count < 1) count = 1;
			var every:Int = s.every != null ? Std.int(s.every) : 1;
			if (every < 1) fail('--every $every: 1 or more');
			sequences.push({dir: s.dir, start: start, count: count, every: every, written: 0, width: 0, height: 0});
			ends.push(start + (count - 1) / fps);
		}
		var sv:Dynamic = Reflect.field(o, "serve");
		serve = sv == null ? null : sv.frames;
		trace = Reflect.field(o, "trace");
		stats = Reflect.field(o, "stats");
		var keys:Null<String> = Reflect.field(o, "keys"), pointer = Reflect.field(o, "pointer") == true;
		overlay = keys != null || pointer ? new Overlay(keys, Reflect.field(o, "keysTheme") ?? (dark ? "dark" : "light"), pointer) : null;
		var e = 0.0;
		for (t in ends)
			if (t > e) e = t;
		end = serve != null ? Math.POSITIVE_INFINITY : ends.length == 0 ? autoEnd() : e;
		wantsPixels = snaps.length > 0 || sequences.length > 0 || serve != null;
		serveStart = haxe.Timer.stamp();
		wantsNodes = trees.length > 0 || trace != null;
		seed(Std.int(num(o, "seed", 1)));
		Time.now = 0;
	}

	static function num(o:Dynamic, name:String, fallback:Float):Float {
		var v:Dynamic = Reflect.field(o, name);
		return v == null ? fallback : Std.isOfType(v, String) ? Std.parseFloat(v) : (v : Float);
	}

	// a time: seconds, "end" (the end mark, else a second after the
	// script's last step, else 1), "mark:<name>", "mark:<name>+0.5"
	function timeOf(spec:Dynamic):Float {
		if (spec == null) return autoEnd();
		if (!Std.isOfType(spec, String)) return (spec : Float);
		var s:String = spec;
		if (s == "end" || s == "auto") return autoEnd();
		if (s.startsWith("mark:")) {
			var m = s.substr(5);
			if (script.marks.exists(m)) return script.marks.get(m);
			var r = ~/^(.*)([+-])([0-9.]+)$/;
			if (r.match(m) && script.marks.exists(r.matched(1))) {
				var off = Std.parseFloat(r.matched(3));
				return script.marks.get(r.matched(1)) + (r.matched(2) == "-" ? -off : off);
			}
			fail('$s: no such mark in the script (${[for (k in script.marks.keys()) k].join(", ")})');
		}
		var f = Std.parseFloat(s);
		if (Math.isNaN(f)) fail('$s: a time is seconds, end or mark:<name>[+<seconds>]');
		return f;
	}

	function autoEnd():Float
		return script.marks.exists("end") ? script.marks.get("end") : script.steps.length > 0 ? script.last + 1 : 1;

	// the frame's time (serve: the machine's since the start)
	inline function frameTime():Float
		return serve != null ? haxe.Timer.stamp() - serveStart : frame / fps;

	// the script's time: the frame's less the time held
	inline function scriptTime():Float
		return frameTime() - shift;

	// the script waits until done() (the program's work outside it: a build,
	// another process's answer), the frames going on; the run fails when a
	// hold lasts seconds of the machine's time
	public function hold(done:Void->Bool, why:String, seconds = 120.0) {
		if (serve != null || done()) return;
		var now = haxe.Timer.stamp();
		holds.push({done: done, why: why, until: now + seconds, since: now});
	}

	// whether a hold is on (its frame waits a little on the machine's clock: what it waits for runs)
	function held():Bool {
		if (holds.length == 0) return false;
		var now = haxe.Timer.stamp();
		for (h in holds.copy())
			if (h.done()) {
				holds.remove(h);
				if (now - h.since > 0.5) Sys.println('headless: held ${Math.round((now - h.since) * 10) / 10} s (${h.why})');
			} else if (now > h.until) fail('held for ${Math.round(now - h.since)} s, never done: ${h.why}');
		if (holds.length == 0) return false;
		shift += 1 / fps;
		Sys.sleep(0.003);
		return true;
	}

	// (HeadlessWindow's)
	public function opened(w:HeadlessWindow)
		windows.push(w);

	// an event of the run's own (a window's Resize), before the script's next
	public function post(e:Event)
		posted.push(e);

	// (a field focused: its caret, where an input method would show)
	public function textInputAt(x:Int, y:Int, w:Int, h:Int) {}

	// the events due by this frame's time, in order: those posted, the
	// script's steps (each turned into acts when it comes: its target found
	// then) and their acts
	public function events(onEvent:Event->Void) {
		if (stats != null) statsBegin();
		if (held()) {
			while (posted.length > 0)
				onEvent(posted.shift());
			Time.now = frameTime();
			return;
		}
		var t = scriptTime() + 1e-9;
		while (true) {
			if (posted.length > 0) {
				onEvent(posted.shift());
				continue;
			}
			var st = stepAt < script.steps.length ? script.steps[stepAt].t : Math.POSITIVE_INFINITY;
			var at = acts.length > 0 ? acts[0].t : Math.POSITIVE_INFINITY;
			if (st > t && at > t) break;
			if (st <= at) {
				var s = script.steps[stepAt++];
				Time.now = s.t + shift;
				expand(s);
			} else {
				var a = acts.shift();
				Time.now = a.t + shift;
				act(a, onEvent);
			}
		}
		Time.now = frameTime();
	}

	function add(a:Act) {
		var i = acts.length;
		while (i > 0 && acts[i - 1].t > a.t)
			i--;
		acts.insert(i, a);
	}

	inline function at(step:Step, t:Float, kind:ActKind):Act {
		var a = new Act(step, t, kind);
		add(a);
		return a;
	}

	// a step's acts, its target found now
	function expand(s:Step) {
		var mods = modsOf(s), button = switch s.str("button") {
			case null | "left": 1;
			case "middle": 2;
			case "right" | "secondary": 3;
			case b: fail('$s: no button $b (left, middle, right)');
		}
		switch s.type {
			case "mark":
			case "move":
				var p = target(s);
				at(s, s.t, Move).pos(p.x, p.y);
			case "down" | "up":
				var p = target(s);
				at(s, s.t, Move).pos(p.x, p.y);
				var a = at(s, s.t, s.type == "down" ? Down : Up).pos(p.x, p.y);
				a.button = button;
				a.mods = mods;
				if (s.type == "down" && overlay != null) overlay.press(s.t, p.x, p.y);
			case "tap" | "double-click":
				var p = target(s), hold = s.num("hold", HOLD), gap = s.num("gap", 0.15);
				at(s, s.t, Move).pos(p.x, p.y);
				for (k in 0...(s.type == "tap" ? 1 : 2)) {
					var d = at(s, s.t + k * gap, Down).pos(p.x, p.y);
					d.button = button;
					d.mods = mods;
					var u = at(s, s.t + k * gap + hold, Up).pos(p.x, p.y);
					u.button = button;
					u.mods = mods;
					if (overlay != null) overlay.press(s.t + k * gap, p.x, p.y);
				}
			case "drag":
				var p = target(s), dx = s.num("dx", 0), dy = s.num("dy", 0), dur = s.num("dur", 0.3);
				at(s, s.t, Move).pos(p.x, p.y);
				var d = at(s, s.t, Down).pos(p.x, p.y);
				d.button = button;
				d.mods = mods;
				if (overlay != null) overlay.press(s.t, p.x, p.y);
				var n = Std.int(Math.max(1, Math.ceil(dur * fps)));
				for (i in 1...n + 1) {
					var k = i / n;
					at(s, s.t + dur * k, Move).pos(p.x + dx * k, p.y + dy * k).mods = mods;
				}
				var u = at(s, s.t + dur + HOLD, Up).pos(p.x + dx, p.y + dy);
				u.button = button;
				u.mods = mods;
			case "wheel":
				var p = target(s);
				at(s, s.t, Move).pos(p.x, p.y);
				var w = at(s, s.t, Wheel).pos(p.x, p.y);
				w.dx = s.num("dx", 0);
				w.dy = s.num("dy", 0);
				w.mods = mods;
			case "key" | "key-up":
				var name = s.str("name");
				var a = at(s, s.t, s.type == "key" ? Key : KeyUp);
				a.key = Script.Keys.code(name);
				a.mods = mods;
				// (a character typed: not with Control, Alt or the Command key)
				if (s.type == "key" && mods & (2 | 4 | 8) == 0) a.text = Script.Keys.text(name, mods & 1 != 0);
				if (s.type == "key" && overlay != null) overlay.key(s.t, Script.Keys.label(name, mods), false);
			case "type":
				var text = s.str("text"), every = s.num("every", 0), i = 0;
				for (c in new haxe.iterators.StringIteratorUnicode(text)) {
					var ch = String.fromCharCode(c);
					var a = at(s, s.t + i * every, Key);
					a.key = Script.Keys.code(ch);
					a.mods = ch != ch.toLowerCase() ? 1 : 0;
					a.text = ch;
					if (overlay != null) overlay.key(s.t + i * every, ch, true);
					i++;
				}
			case "resize":
				var w = mainWindow(s);
				var tw:Float = s.num("width", w.width + s.num("dw", 0)), th:Float = s.num("height", w.height + s.num("dh", 0));
				var dur = s.num("dur", 0), fw = w.width, fh = w.height;
				var n = dur <= 0 ? 1 : Std.int(Math.max(1, Math.ceil(dur * fps)));
				for (i in 1...n + 1) {
					var k = i / n, e = 1 - (1 - k) * (1 - k);
					var a = at(s, s.t + dur * k, Resize);
					a.x = Math.round(fw + (tw - fw) * (dur <= 0 ? 1 : e));
					a.y = Math.round(fh + (th - fh) * (dur <= 0 ? 1 : e));
				}
			case "menu-pick":
				var a = at(s, s.t, MenuPick);
				a.text = s.str("label");
				a.key = s.data.id == null ? -1 : Std.int(s.data.id);
			case "menu-cancel":
				at(s, s.t, MenuCancel);
			case "literal":
				#if hxmc.dev
				// (a live literal: by id, else by file, value and line; patched now, the next frame shows it)
				var id = s.str("id"), file = s.str("file"), value:Dynamic = s.data.value, line:Dynamic = s.data.line;
				var found = Lambda.find(helder.dev.Literals.list(), l -> id != null ? l.id == id : (file == null || StringTools.endsWith(l.file, file))
					&& (value == null || l.base == value) && (line == null || l.line == line));
				if (found == null) failStep(s, 'no live literal ${id ?? (file ?? "") + (value == null ? "" : " of " + Std.string(value))} read by this time');
				helder.dev.Literals.patch([{id: found.id, value: s.data.set}]);
				#else
				fail('$s: a literal step patches a dev build\'s live literals: helder run --headless --dev');
				#end
			case "file-dialog" | "file-dialog-cancel":
			// (FileDialog.open takes the next answer whenever it asks)
			case t:
				fail('$s: $t is not done headless yet');
		}
	}

	function act(a:Act, onEvent:Event->Void) {
		var k = mainWindow(a.step).scale;
		var e = event;
		e.window = windows[0].window;
		e.mods = a.mods;
		e.text = "";
		e.key = 0;
		e.button = 0;
		e.deltaX = e.deltaY = 0;
		e.x = Math.round(a.x * k);
		e.y = Math.round(a.y * k);
		if (stats != null) switch a.kind {
			case Key | KeyUp: statKeys++;
			case Wheel: statWheels++;
			case Move | Down | Up: statPointers++;
			case _:
		}
		switch a.kind {
			case Move:
				px = a.x;
				py = a.y;
				e.kind = MouseMove;
				onEvent(e);
			case Down:
				px = a.x;
				py = a.y;
				e.kind = MouseDown;
				e.button = a.button;
				onEvent(e);
			case Up:
				px = a.x;
				py = a.y;
				e.kind = MouseUp;
				e.button = a.button;
				onEvent(e);
			case Wheel:
				e.kind = Scroll;
				e.deltaX = a.dx * k;
				e.deltaY = a.dy * k;
				onEvent(e);
			case Key:
				e.kind = KeyDown;
				e.key = a.key;
				onEvent(e);
				if (a.text != null && a.text != "") {
					e.kind = TextInput;
					e.window = windows[0].window;
					e.key = 0;
					e.text = a.text;
					onEvent(e);
				}
				e.kind = KeyUp;
				e.window = windows[0].window;
				e.text = "";
				e.key = a.key;
				e.mods = a.mods;
				onEvent(e);
			case KeyUp:
				e.kind = KeyUp;
				e.key = a.key;
				onEvent(e);
			case Resize:
				windows[0].resize(Std.int(a.x), Std.int(a.y));
			case MenuPick:
				var why = inspector == null ? "no node tree: this window has no pop-up menus" : inspector.menuPick(a.key < 0 ? null : a.key, a.text);
				if (why != null) failStep(a.step, why);
			case MenuCancel:
				if (inspector == null || !inspector.menuCancel()) failStep(a.step, "no pop-up menu is open");
		}
	}

	// helder.os.FileDialog's answer: the script's next file-dialog step's path (null: cancelled, or none left)
	public function fileDialog(title:String):Null<String> {
		var s = answers.shift();
		if (s == null) {
			Sys.println('headless: a file dialog ($title) at ${round(Time.now)} s, no file-dialog step left: cancelled');
			return null;
		}
		return s.type == "file-dialog" ? s.str("path") : null;
	}

	function mainWindow(s:Step):HeadlessWindow {
		if (windows.length == 0) failStep(s, "the program has no window yet");
		return windows[0];
	}

	function modsOf(s:Step):Int {
		var m = 0;
		if (s.flag("shift")) m |= Mods.SHIFT;
		if (s.flag("ctrl") || s.flag("control")) m |= Mods.CONTROL;
		if (s.flag("alt") || s.flag("option")) m |= Mods.ALT;
		if (s.flag("cmd") || s.flag("meta")) m |= Mods.META;
		// (secondary: Command on a Mac, Control elsewhere, as Keymap's)
		if (s.flag("secondary")) m |= hxmc.unsafe.Mem.os() == 1 ? Mods.META : Mods.CONTROL;
		return m;
	}

	// where a step aims (points): its node's centre (or ox, oy from its top left), x, y, else the pointer
	function target(s:Step):{x:Float, y:Float} {
		var tag = s.str("tag"), path = s.str("path"), role = s.str("role"), label = s.str("label");
		if (tag == null && path == null && role == null && label == null) {
			if (Reflect.hasField(s.data, "x") || Reflect.hasField(s.data, "y")) return {x: s.num("x", px), y: s.num("y", py)};
			return {x: px, y: py};
		}
		if (inspector == null) failStep(s, 'aims at ${s.target()}, but this window has no node tree (a scene\'s, gfx\'s): aim at x, y');
		var nodes = inspector.nodes();
		var n = find(nodes, tag, path, role, label, Std.int(s.num("index", 0)));
		if (n == null) {
			var tags = [];
			for (x in nodes)
				if (!GENERIC.contains(x.tag) && !tags.contains(x.tag)) tags.push(x.tag);
			failStep(s, 'no node ${s.target()} (tags shown: ${tags.slice(0, 40).join(", ")})');
		}
		if (n.width <= 0 || n.height <= 0 || n.opacity <= 0) failStep(s, '${s.target()} is not shown (${n.width}x${n.height}, opacity ${n.opacity})');
		var x = Reflect.hasField(s.data, "ox") ? n.x + s.num("ox", 0) : n.x + n.width / 2;
		var y = Reflect.hasField(s.data, "oy") ? n.y + s.num("oy", 0) : n.y + n.height / 2;
		return {x: x, y: y};
	}

	// the tags every element has unless given one (left out of a trace and of hints)
	public static final GENERIC = ["view", "text", "span", "b", "i", "scroll", "overlay"];

	// the index'th node of that tag, or whose tags end with path (a
	// descendant chain: "list/checkbox"), of that role (ARIA's: "checkbox")
	// and label (its accessible name, else its text); each that is given
	public static function find(nodes:Array<InspectedNode>, tag:Null<String>, path:Null<String>, role:Null<String>, label:Null<String>, index:Int):Null<InspectedNode> {
		var byId = new Map<Int, InspectedNode>();
		for (n in nodes)
			byId.set(n.id, n);
		var parts = path != null ? path.split("/") : tag != null ? [tag] : [];
		var k = 0;
		for (n in nodes) {
			if (role != null && n.role != role) continue;
			if (label != null && (n.label ?? n.text) != label) continue;
			if (parts.length == 0) {
				if (k++ == index) return n;
				continue;
			}
			if (n.tag != parts[parts.length - 1]) continue;
			var i = parts.length - 2, up = byId.get(n.parent);
			while (i >= 0 && up != null) {
				if (up.tag == parts[i]) i--;
				up = byId.get(up.parent);
			}
			if (i >= 0) continue;
			if (k++ == index) return n;
		}
		return null;
	}

	// (Device.endFrame's, for a headless surface: the first window's frame read)
	public function present(surface:Surface, w:Int, h:Int, read:Bytes->Void) {
		if (!wantsPixels || windows.length == 0 || windows[0].surface != surface) return;
		if (pixels == null || pixelsWidth != w || pixelsHeight != h) {
			pixels = Bytes.alloc(w * h * 4);
			pixelsWidth = w;
			pixelsHeight = h;
		}
		read(pixels);
		if (serve != null) serveFrame();
	}

	// (serve) the frame drawn, written beside the file and renamed over it, then told
	function serveFrame() {
		served++;
		var head = Bytes.alloc(16);
		head.blit(0, Bytes.ofString("HLDF"), 0, 4);
		head.setInt32(4, pixelsWidth);
		head.setInt32(8, pixelsHeight);
		head.setInt32(12, served);
		var tmp = serve + ".tmp";
		mkdirs(haxe.io.Path.directory(serve));
		var f = sys.io.File.write(tmp, true);
		f.writeBytes(head, 0, 16);
		f.writeBytes(pixels, 0, pixels.length);
		f.close();
		sys.FileSystem.rename(tmp, serve);
		#if hxmc.dev
		helder.devtools.Agent.notify("Headless.frame", {version: served, width: pixelsWidth, height: pixelsHeight, path: serve});
		#end
	}

	// after a frame: its outputs; whether the run goes on
	public function framed():Bool {
		if (stats != null) statsEnd();
		if (serve != null) {
			// (paced: the next frame 1/fps after the last's, on the machine's clock)
			frame++;
			var wait = frame / fps - frameTime();
			if (wait > 0) Sys.sleep(Math.min(wait, 1 / fps)) else frame = Std.int(frameTime() * fps);
			return true;
		}
		var t = scriptTime(), eps = 1e-6;
		var nodes:Null<Array<InspectedNode>> = null;
		if (wantsNodes && inspector != null) nodes = inspector.nodes();
		for (s in snaps)
			if (!s.done && s.at <= t + eps) {
				s.done = true;
				writePng(s.path, t);
				Sys.println('headless: ${s.path} at ${round(t)} s');
			}
		for (s in trees)
			if (!s.done && s.at <= t + eps) {
				s.done = true;
				writeTree(s.path, t, nodes);
				Sys.println('headless: ${s.path} at ${round(t)} s');
			}
		for (q in sequences)
			if (q.written < q.count && q.start <= t + eps) {
				var i = q.written++;
				if (q.width == 0) {
					q.width = pixelsWidth;
					q.height = pixelsHeight;
				}
				if (i % q.every == 0) writePng(q.dir + "/frame_" + StringTools.lpad(Std.string(i), "0", 4) + ".png", t, q.width, q.height);
			}
		if (trace != null) traceFrame(t, nodes);
		if (nodes != null) {
			last = new Map();
			for (n in nodes)
				last.set(n.id, n);
		}
		frame++;
		if (scriptTime() > end + eps) {
			finish();
			return false;
		}
		return true;
	}

	// the run's end (its last frame, or the program closed its windows): what is left written, what was never reached said
	public function finish() {
		if (finished) return;
		finished = true;
		if (traceOut != null) traceOut.close();
		if (stats != null) writeStats();
		var missed = [for (s in snaps.concat(trees)) if (!s.done) '${s.path} (at ${round(s.at)} s)'];
		for (q in sequences)
			if (q.written < q.count) missed.push('${q.dir} (${q.written} of ${q.count} frames)');
		var left = [for (i in stepAt...script.steps.length) script.steps[i]].filter(s -> s.t <= end);
		Sys.println('headless: $frame frames, 0 to ${round((frame - 1) / fps)} s');
		if (missed.length > 0) {
			Sys.stderr().writeString('helder headless: the program ended at ${round(Time.now)} s, before ${missed.join(", ")}\n');
			Sys.exit(1);
		}
		if (left.length > 0) {
			Sys.stderr().writeString('helder headless: the program ended at ${round(Time.now)} s, before ${left[0]}\n');
			Sys.exit(1);
		}
	}

	// (a frame's work begins: its events; the collector's counters then)
	function statsBegin() {
		statStart = haxe.Timer.stamp();
		#if (target.name == "hxmc")
		statBytes = hxmc.GcStats.bytesAllocated();
		statCollections = hxmc.GcStats.collections();
		#end
		statKeys = statWheels = statPointers = 0;
		helder.gfx.FrameCounts.reset();
	}

	// (and ends, drawn: before its outputs are written)
	function statsEnd() {
		if (statStart < 0) return;
		var ms = (haxe.Timer.stamp() - statStart) * 1000, bytes = 0.0, gcs = 0;
		#if (target.name == "hxmc")
		bytes = hxmc.GcStats.bytesAllocated() - statBytes;
		gcs = hxmc.GcStats.collections() - statCollections;
		#end
		var f = statFrames, g = helder.gfx.FrameCounts;
		f.push(frame);
		f.push(frameTime());
		f.push(ms);
		f.push(bytes);
		f.push(gcs);
		f.push(statKeys);
		f.push(statWheels);
		f.push(statPointers);
		f.push(g.passes);
		f.push(g.draws);
		f.push(g.instances);
		f.push(g.pipelines);
		f.push(g.textures);
		f.push(g.quads);
		f.push(g.uiMs);
		f.push(g.uploadMs);
		f.push(g.encodeMs);
		f.push(g.uploaded);
		f.push(g.uiBytes);
		statStart = -1;
	}

	// {"fps", "frames": [{"frame", "t", "ms", "gcBytes", "gcs", "keys", "wheels", "pointers",
	// "passes", "draws", "instances", "pipelines", "textures", "quads", "uiMs", "uploadMs", "encodeMs", "uploaded", "uiBytes"}...]}
	function writeStats() {
		var b = new StringBuf();
		b.add('{"fps":$fps,"frames":[');
		var k = 0, n = STAT_FIELDS;
		var drawn:Array<Array<Float>> = [];
		while (k + n - 1 < statFrames.length) {
			if (k > 0) b.add(",\n");
			var f = statFrames;
			b.add('{"frame":${Std.int(f[k])},"t":${round(f[k + 1])},"ms":${Math.round(f[k + 2] * 1000) / 1000},"gcBytes":${Std.int(f[k + 3])},"gcs":${Std.int(f[k + 4])},"keys":${Std.int(f[k + 5])},"wheels":${Std.int(f[k + 6])},"pointers":${Std.int(f[k + 7])}');
			b.add(',"passes":${Std.int(f[k + 8])},"draws":${Std.int(f[k + 9])},"instances":${Std.int(f[k + 10])},"pipelines":${Std.int(f[k + 11])},"textures":${Std.int(f[k + 12])},"quads":${Std.int(f[k + 13])},"uiMs":${Math.round(f[k + 14] * 1000) / 1000},"uploadMs":${Math.round(f[k + 15] * 1000) / 1000},"encodeMs":${Math.round(f[k + 16] * 1000) / 1000},"uploaded":${Std.int(f[k + 17])},"uiBytes":${Std.int(f[k + 18])}}');
			if (f[k + 8] > 0) drawn.push([f[k + 2], f[k + 8], f[k + 9], f[k + 13], f[k + 14], f[k + 3], f[k + 14] - f[k + 16], f[k + 16], f[k + 18]]);
			k += n;
		}
		b.add("]}\n");
		var dir = haxe.io.Path.directory(stats);
		if (dir != "" && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(stats, b.toString());
		Sys.println('headless: $stats (${Std.int(statFrames.length / n)} frames)');
		// (the frames drawn: each column's median and largest)
		if (drawn.length > 0) {
			function col(i:Int, q:Float):Float {
				var v = [for (d in drawn) d[i]];
				v.sort(Reflect.compare);
				return v[Std.int(Math.min(v.length - 1, v.length * q))];
			}
			function ms(v:Float)
				return Math.round(v * 1000) / 1000;
			Sys.println('headless: ${drawn.length} frames drawn: passes ${col(1, 0.5)} (at most ${col(1, 1)}), draw calls ${col(2, 0.5)} (at most ${col(2, 1)}), quads ${col(3, 0.5)}, renderer CPU ms ${ms(col(4, 0.5))} (p95 ${ms(col(4, 0.95))}, of it the draw calls ${ms(col(7, 0.5))}, the rest ${ms(col(6, 0.5))}), frame ms ${ms(col(0, 0.5))} (p95 ${ms(col(0, 0.95))}), GC bytes ${col(5, 0.5)} (the renderer, painting included, ${col(8, 0.5)})');
		}
	}

	static inline var STAT_FIELDS = 19;

	// the frame (keycaps and ripples over it) as an opaque PNG; at w x h pixels when given (cropped or padded with black)
	function writePng(path:String, t:Float, w = 0, h = 0) {
		if (pixels == null) fail('$path: no frame was drawn by ${round(t)} s');
		var out = pixels;
		if (overlay != null) {
			out = Bytes.alloc(pixels.length);
			out.blit(0, pixels, 0, pixels.length);
			overlay.draw(out, pixelsWidth, pixelsHeight, windows[0].scale, t, dark);
		}
		if (w == 0) {
			w = pixelsWidth;
			h = pixelsHeight;
		}
		if (w != pixelsWidth || h != pixelsHeight) {
			var fit = Bytes.alloc(w * h * 4), cw = Std.int(Math.min(w, pixelsWidth));
			for (y in 0...Std.int(Math.min(h, pixelsHeight)))
				fit.blit(y * w * 4, out, y * pixelsWidth * 4, cw * 4);
			out = fit;
		}
		mkdirs(haxe.io.Path.directory(path));
		sys.io.File.saveBytes(path, helder.image.PngEncoder.encode(out, w, h, true));
	}

	function writeTree(path:String, t:Float, nodes:Null<Array<InspectedNode>>) {
		var w = windows.length > 0 ? windows[0] : null;
		var b = new StringBuf();
		b.add('{\n  "time": ${round(t)},\n  "frame": $frame,\n');
		if (w != null) b.add('  "size": {"width": ${w.width}, "height": ${w.height}, "scale": ${num2(w.scale)}},\n');
		b.add('  "pointer": {"x": ${num2(px)}, "y": ${num2(py)}},\n');
		if (nodes == null) {
			b.add('  "nodes": null\n}\n');
		} else {
			b.add('  "nodes": [');
			for (i in 0...nodes.length) {
				b.add(i == 0 ? "\n    " : ",\n    ");
				b.add(nodeJson(nodes[i], true));
			}
			b.add('\n  ]\n}\n');
		}
		mkdirs(haxe.io.Path.directory(path));
		sys.io.File.saveContent(path, b.toString());
	}

	// whether it moved since the last frame, or a transition is moving it
	function moving(n:InspectedNode):Bool {
		if (n.transitioning) return true;
		var o = last.get(n.id);
		return o != null && (o.x != n.x || o.y != n.y || o.width != n.width || o.height != n.height || o.opacity != n.opacity);
	}

	function nodeJson(n:InspectedNode, full:Bool):String {
		var b = new StringBuf();
		b.add('{"id": ${n.id}, "tag": ${str(n.tag)}, "path": ${str(n.path)}');
		if (full) {
			b.add(', "parent": ${n.parent}, "depth": ${n.depth}');
			if (n.role != null) b.add(', "role": ${str(n.role)}');
			if (n.label != null && n.label != "") b.add(', "label": ${str(n.label)}');
			if (n.text != null) b.add(', "text": ${str(n.text)}');
			if (n.value != null) b.add(', "value": ${str(n.value)}');
			if (n.checked != null) b.add(', "checked": ${n.checked}');
			if (n.selected != null) b.add(', "selected": ${n.selected}');
			if (n.setSize > 0) b.add(', "posinset": ${n.posInSet}, "setsize": ${n.setSize}');
			if (n.disabled) b.add(', "disabled": true');
		}
		b.add(', "rect": [${num2(n.x)}, ${num2(n.y)}, ${num2(n.width)}, ${num2(n.height)}], "opacity": ${num2(n.opacity)}');
		if (full) {
			if (n.fill != null) b.add(', "fill": ${str(n.fill)}');
			if (n.color != null) b.add(', "color": ${str(n.color)}');
			b.add(', "hover": ${n.hover}, "press": ${n.press}, "focus": ${n.focus}');
			if (n.source != null) b.add(', "source": ${sourceJson(n.source)}');
			if (n.component != null) {
				var c = n.component;
				b.add(', "component": {"name": ${str(c.name)}, "call": ${sourceJson(c.call)}, "definition": ${c.definition == null ? "null" : sourceJson(c.definition)}}');
			}
		}
		b.add(', "moving": ${moving(n)}}');
		return b.toString();
	}

	// {"file", "line", "col", "end": {"line", "col"}, "offsets": [start, end]}
	static function sourceJson(s:helder.view.Source):String
		return '{"file": ${str(s.file)}, "line": ${s.line}, "col": ${s.col}, "end": {"line": ${s.endLine}, "col": ${s.endCol}}, "offsets": [${s.start}, ${s.end}]}';

	function traceFrame(t:Float, nodes:Null<Array<InspectedNode>>) {
		if (traceOut == null) {
			mkdirs(haxe.io.Path.directory(trace));
			traceOut = sys.io.File.write(trace);
		}
		var b = new StringBuf();
		b.add('{"t": ${round(t)}, "frame": $frame, "nodes": [');
		var first = true;
		if (nodes != null)
			for (n in nodes) {
				if (GENERIC.contains(n.tag)) continue;
				if (!first) b.add(", ");
				first = false;
				b.add(nodeJson(n, false));
			}
		b.add("]}\n");
		traceOut.writeString(b.toString());
	}

	static function str(s:String):String
		return haxe.Json.stringify(s);

	// (seconds to the microsecond)
	static function round(t:Float):String
		return fmt(Math.round(t * 1e6) / 1e6);

	// (two decimals: the layout's sub-pixel noise out)
	static function num2(v:Float):String
		return fmt(Math.round(v * 100) / 100);

	static function fmt(v:Float):String {
		if (v == Math.ffloor(v) && Math.abs(v) < 1e15) return Std.string(Std.int(v));
		return Std.string(v);
	}

	static function mkdirs(d:String) {
		if (d == "" || sys.FileSystem.exists(d)) return;
		mkdirs(haxe.io.Path.directory(d));
		sys.FileSystem.createDirectory(d);
	}

	function failStep(s:Step, message:String):Dynamic
		return fail('$s: $message');

	static function fail(message:String):Dynamic {
		Sys.stderr().writeString('helder headless: $message\n');
		Sys.exit(1);
		return null;
	}

	// Math.random's (and Std.random's) sequence from n: hxmc's xoshiro256**
	// state, splitmix64 of the seed, as hxmc seeds it from the time
	@:hxmc.unsafe static function seed(n:Int) {
		var x = hxmc.unsafe.Mem.stack(8);
		hxmc.unsafe.Mem.setI64(x, 0, (n : hxmc.I64));
		@:privateAccess {
			hxmc.rt.Random.s0 = hxmc.rt.Random.splitmix(x);
			hxmc.rt.Random.s1 = hxmc.rt.Random.splitmix(x);
			hxmc.rt.Random.s2 = hxmc.rt.Random.splitmix(x);
			hxmc.rt.Random.s3 = hxmc.rt.Random.splitmix(x);
		}
	}
}

enum ActKind {
	Move;
	Down;
	Up;
	Wheel;
	Key;
	KeyUp;
	Resize;
	MenuPick;
	MenuCancel;
}

// one event of a step, due at t
class Act {
	public final step:Step;
	public final t:Float;
	public final kind:ActKind;
	public var x = 0.0;
	public var y = 0.0;
	public var dx = 0.0;
	public var dy = 0.0;
	public var button = 0;
	public var key = 0;
	public var mods = 0;
	public var text:Null<String> = null;

	public function new(step:Step, t:Float, kind:ActKind) {
		this.step = step;
		this.t = t;
		this.kind = kind;
	}

	public function pos(x:Float, y:Float):Act {
		this.x = x;
		this.y = y;
		return this;
	}
}
