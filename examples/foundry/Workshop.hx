import Model;
import helder.os.Store;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// Foundry's state: the face and its history, the glyph on the board, the
// tool, what is selected, the preview's text; every edit (the board's,
// the panels', an agent's) goes through edit, so each is undoable and
// saved (helder.os's Store: the app's data folder, localStorage on the
// web), and the draft font follows it.
class Workshop {
	public final face:Signal<Face>;
	public final current = signal("n");
	// "draw", "adjust", "erase"
	public final tool = signal("draw");
	// the tracing letter behind the board
	public final guide = signal(true);
	// the selected line and knot (knot -1: the whole line)
	public final selected:Signal<Null<{line:Int, knot:Int}>> = signal(null);
	public final sample = signal("Hamburgefonstiv");
	public final size = signal(56.0);
	// "system", "light", "dark"
	public final appearance = signal("system");
	public final dark:Read<Bool>;
	public final canUndo = signal(false);
	public final canRedo = signal(false);
	// a word in the status bar, and whether it is a problem
	public final status = signal("");
	// where agents reach the app (Mcp), "" while there is none
	public final mcp = signal("");
	// what an agent did last (shown on the board)
	public final agent = signal("");

	// (the face after the last edit, at once: a signal's write lands at the
	// end of the event, and an agent's call reads back what it just did)
	var latest:Face;
	final past:Array<Face> = [];
	final future:Array<Face> = [];
	var lastGroup = "";
	var lastAt = 0.0;
	final store:Store;

	public function new() {
		store = Store.open("foundry");
		var saved = store.get("face");
		latest = saved == null ? Sample.face() : Model.load(saved) ?? Sample.face();
		face = signal(latest);
		appearance(store.get("appearance") ?? "system");
		dark = memo(() -> appearance() == "dark" || appearance() == "system" && helder.ui.draw.UiWindow.dark());
		// (saved a moment after the last change: a drag saves once)
		var timer:Null<haxe.Timer> = null;
		effect(() -> face(), f -> {
			Draft.show(f);
			if (timer != null) timer.stop();
			timer = haxe.Timer.delay(() -> store.set("face", Model.save(latest)), 400);
		});
	}

	// a new face: undoable; edits of the same group within a second are one step (a slider's drag)
	public function edit(next:Face, ?group:String) {
		var now = haxe.Timer.stamp(), prev = latest;
		if (next == prev) return;
		if (group == null || group != lastGroup || now - lastAt > 1.0) {
			past.push(prev);
			if (past.length > 200) past.shift();
		}
		future.resize(0);
		lastGroup = group ?? "";
		lastAt = now;
		face(latest = next);
		canUndo(past.length > 0);
		canRedo(false);
	}

	public function undo() {
		var f = past.pop();
		if (f == null) return;
		future.push(latest);
		lastGroup = "";
		face(latest = f);
		selected(null);
		canUndo(past.length > 0);
		canRedo(true);
	}

	public function redo() {
		var f = future.pop();
		if (f == null) return;
		past.push(latest);
		lastGroup = "";
		face(latest = f);
		selected(null);
		canUndo(true);
		canRedo(future.length > 0);
	}

	public function open(char:String) {
		if (char == current.peek()) return;
		current(char);
		selected(null);
	}

	public function appear(kind:String) {
		appearance(kind);
		store.set("appearance", kind);
	}

	// ---- a glyph's edits

	// char's glyph as stored, else what it shows (its suggestion's parts)
	public function glyph(char:String):Glyph {
		var f = latest;
		return Model.glyph(f, char) ?? {lines: [], parts: Charset.borrow(f, char)};
	}

	public function setGlyph(char:String, g:Glyph, ?group:String)
		edit(Model.with(latest, char, g), group);

	public function addLine(char:String, line:Line) {
		var g = glyph(char);
		setGlyph(char, {lines: g.lines.concat([line]), parts: g.parts, left: g.left, right: g.right});
	}

	public function removeLine(char:String, i:Int) {
		var g = glyph(char);
		if (i < 0 || i >= g.lines.length) return;
		setGlyph(char, {lines: [for (k in 0...g.lines.length) if (k != i) g.lines[k]], parts: g.parts, left: g.left, right: g.right});
		selected(null);
	}

	public function setLine(char:String, i:Int, line:Line, ?group:String) {
		var g = glyph(char);
		if (i < 0 || i >= g.lines.length) return;
		setGlyph(char, {lines: [for (k in 0...g.lines.length) k == i ? line : g.lines[k]], parts: g.parts, left: g.left, right: g.right}, group);
	}

	public function moveKnot(char:String, line:Int, knot:Int, x:Float, y:Float, ?group:String) {
		var l = glyph(char).lines[line];
		if (l == null || knot < 0 || knot >= l.knots.length) return;
		var ks = l.knots.copy();
		ks[knot] = {x: x, y: y, corner: ks[knot].corner};
		setLine(char, line, {knots: ks, closed: l.closed}, group);
	}

	public function toggleCorner(char:String, line:Int, knot:Int) {
		var l = glyph(char).lines[line];
		if (l == null || knot < 0 || knot >= l.knots.length) return;
		var ks = l.knots.copy();
		ks[knot] = {x: ks[knot].x, y: ks[knot].y, corner: ks[knot].corner != true};
		setLine(char, line, {knots: ks, closed: l.closed});
	}

	// the selected knot gone (a line of one knot with it), or the selected line
	public function deleteSelected() {
		var s = selected.peek(), char = current.peek();
		if (s == null) return;
		var l = glyph(char).lines[s.line];
		if (l == null) return;
		if (s.knot < 0 || l.knots.length <= 1) return removeLine(char, s.line);
		setLine(char, s.line, {knots: [for (k in 0...l.knots.length) if (k != s.knot) l.knots[k]], closed: l.closed == true && l.knots.length > 3});
		selected(null);
	}

	public function setSpacing(char:String, left:Float, right:Float, ?group:String) {
		var g = glyph(char);
		setGlyph(char, {lines: g.lines, parts: g.parts, left: left, right: right}, group);
	}

	// what it borrows made its own lines (to change them)
	public function adopt(char:String) {
		var f = latest, g = glyph(char);
		setGlyph(char, {lines: Ink.lines(f, char), parts: [], left: g.left, right: g.right});
	}

	// nothing borrowed: an empty glyph to draw
	public function own(char:String) {
		var g = glyph(char);
		setGlyph(char, {lines: g.lines, parts: [], left: g.left, right: g.right});
	}

	// back to empty, or to what it would borrow
	public function clear(char:String) {
		edit(Model.with(latest, char, null));
		selected(null);
	}

	public function setPen(p:Pen, ?group:String)
		edit(refit(latest, p, latest.metrics), group);

	public function setMetrics(m:Metrics, ?group:String)
		edit(refit(latest, latest.pen, m), group);

	// the face with another pen or proportions, every knot moved with the
	// guides around it (a knot on the x-height stays on it; one between
	// the baseline and the x-height keeps its place between them): the
	// whole font reshaped as a slider moves
	static function refit(f:Face, pen:Pen, m:Metrics):Face {
		var h0 = Ink.vertical(f.pen), h1 = Ink.vertical(pen), m0 = f.metrics;
		var glyphs:haxe.DynamicAccess<Glyph> = {};
		for (char => g in f.glyphs) {
			var tall = Charset.tall(char);
			var from = [m0.descender + h0, h0, (tall ? m0.capHeight : m0.xHeight) - h0, m0.ascender - h0];
			var to = [m.descender + h1, h1, (tall ? m.capHeight : m.xHeight) - h1, m.ascender - h1];
			if (tall) {
				from.pop();
				to.pop();
			}
			glyphs.set(char, {
				lines: [for (l in g.lines) {knots: [for (k in l.knots) {x: k.x, y: remap(k.y, from, to), corner: k.corner}], closed: l.closed}],
				parts: g.parts,
				left: g.left,
				right: g.right
			});
		}
		return {name: f.name, pen: pen, metrics: m, glyphs: glyphs};
	}

	// y moved piecewise between anchors (outside them, with the nearest)
	static function remap(y:Float, from:Array<Float>, to:Array<Float>):Float {
		if (y <= from[0]) return y + to[0] - from[0];
		for (i in 1...from.length)
			if (y <= from[i]) {
				var t = (y - from[i - 1]) / Math.max(1e-6, from[i] - from[i - 1]);
				return to[i - 1] + (to[i] - to[i - 1]) * t;
			}
		var last = from.length - 1;
		return y + to[last] - from[last];
	}

	// ---- the font out

	// the font as a .ttf where downloads go (the browser's own download)
	public function export() {
		var f = latest, name = file(f);
		var where = helder.os.Downloads.save(name, Draft.encode(f), "font/ttf");
		say(where == null ? "Could not save the font here" : 'Exported $where');
	}

	// the font where this system's apps find it (macOS, Linux)
	public function install() {
		var f = latest, home = Sys.getEnv("HOME");
		var dir = Sys.systemName() == "Mac" ? '$home/Library/Fonts' : '$home/.local/share/fonts';
		try {
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveBytes('$dir/${file(f)}', Draft.encode(f));
			say('Installed ${f.name}: it is in your fonts now');
		} catch (e:Dynamic) {
			say('Could not install the font ($e)');
		}
	}

	public static function canInstall():Bool
		return #if (hxmc.target == "wasm32-wasi") false #else Sys.systemName() == "Mac" || Sys.systemName() == "Linux" #end;

	static function file(f:Face):String {
		var n = ~/[\\\/:*?"<>|]/g.replace(StringTools.trim(f.name), "");
		return (n == "" ? "Untitled" : n) + ".ttf";
	}

	public function rename(name:String)
		edit(Model.named(latest, name), "name");

	// a fresh face, empty or the sample
	public function start(sample:Bool) {
		edit(sample ? Sample.face() : Model.empty(latest.name));
		open(Charset.start[0]);
	}

	// ---- reading

	// "drawn", "borrowed" or "empty"
	public static function state(f:Face, char:String):String
		return Model.drawn(f, char) ? "drawn" : Ink.lines(f, char).length > 0 ? "borrowed" : "empty";

	public function progress():{drawn:Int, borrowed:Int, total:Int} {
		var f = face(), drawn = 0, borrowed = 0;
		for (c in Charset.all)
			switch state(f, c) {
				case "drawn": drawn++;
				case "borrowed": borrowed++;
				case _:
			}
		return {drawn: drawn, borrowed: borrowed, total: Charset.all.length};
	}

	// the face now, with every edit made so far (what an agent reads)
	public function value():Face
		return latest;

	public function say(text:String)
		status(text);
}
