import Light;
import Play;
import Sketch.*;
import Way;
import helder.canvas.Painter;
import helder.canvas.gpu.GpuCanvas;
import helder.gfx.Device;
import helder.os.*;

// The greybox prototypes' shell: a title (A: Light, B: Way, and the old
// game), the screens of the chosen one in turn, a bar (menu, the screen,
// reset), the fixed steps, a fade between screens. Laid out in points;
// the board fitted between the bar and the hint, whatever the window.
// (play/greybox.mjs has the same numbers: the scripts' taps.)
class Greybox {
	static inline var BAR = 56.0;
	static inline var FOOT = 44.0;
	static inline var EDGE = 14.0;
	static inline var BACK = 0xFF0B0C14;
	static inline var INK = 0xFFE6E3F0;

	final window:Window;
	final device:Device;
	var canvas:Null<GpuCanvas> = null;
	public var log = false;
	// "": the title; "a", "b": a prototype; "game": the old game
	var proto = "";
	var index = 0;
	var play:Null<Play> = null;
	var old:Null<Afterglow> = null;
	var oldStart = -1.0;
	var clock = 0.0;
	var time = 0.0;
	var solvedAt = -1.0;
	var fade = 1.0;
	var leaving = false;
	var buttons:Array<{x:Float, y:Float, w:Float, h:Float, act:() -> Void}> = [];
	var touched = false;

	public function new(window:Window, device:Device) {
		this.window = window;
		this.device = device;
	}

	function screens():Int
		return proto == "a" ? Light.screens.length : Way.screens.length;

	public function choose(p:String, k = 0) {
		proto = p;
		play = null;
		if (p == "a" || p == "b") start(Std.int(Math.max(0, Math.min(k, screens() - 1))));
		if (p == "game" && old == null) {
			old = new Afterglow(device);
			old.points = window.scale;
			old.game.log = log;
			old.sheet = Sys.args().indexOf("--sheet") >= 0;
		}
	}

	function start(k:Int) {
		index = k;
		play = proto == "a" ? new Light(k) : new Way(k);
		solvedAt = -1;
		leaving = false;
		say('start');
	}

	function say(what:String)
		if (log) Sys.println('greybox: $proto${index + 1}: $what at ${Math.round(clock * 10) / 10} s');

	function name():String
		return proto == "a" ? Light.screens[index].name : Way.screens[index].name;

	function hint():String
		return proto == "a" ? Light.screens[index].hint : Way.screens[index].hint;

	// ---- the frame

	public function frame(t:Float) {
		if (proto == "game") {
			var o = old;
			if (o == null) return;
			if (oldStart < 0) oldStart = t;
			var enc = device.beginFrame();
			if (enc == null) return;
			o.draw(enc, t - oldStart);
			device.endFrame();
			return;
		}
		update(t);
		var w = device.width, h = device.height;
		var c = canvas;
		if (c == null || c.width != w || c.height != h) canvas = c = new GpuCanvas(w, h, device);
		var s = window.scale;
		c.resetTransform();
		c.fillRect(0, 0, w, h, helder.canvas.Paint.solid(BACK));
		c.setTransform(s, 0, 0, s, 0, 0);
		buttons = [];
		var pw = w / s, ph = h / s;
		if (play == null) title(c, pw, ph) else game(c, pw, ph);
		c.present();
	}

	function update(t:Float) {
		while (clock + Puzzle.STEP <= t) {
			clock += Puzzle.STEP;
			time += Puzzle.STEP;
			var p = play;
			if (p == null) continue;
			p.step(Puzzle.STEP);
			for (e in p.events)
				say(e);
			p.events.resize(0);
			if (p.solved && solvedAt < 0) solvedAt = clock;
			if (solvedAt >= 0 && clock - solvedAt > 3 && index < screens() - 1) leaving = true;
			if (leaving) {
				fade = Math.min(1, fade + Puzzle.STEP / 0.5);
				if (fade >= 1) start(index + 1);
			} else fade = Math.max(0, fade - Puzzle.STEP / 0.6);
		}
	}

	function title(c:Painter, w:Float, h:Float) {
		var x = w / 2, y = h * 0.24;
		text(c, "AFTERGLOW", x, y, 30, INK);
		text(c, "GREYBOX PROTOTYPES", x, y + 34, 11, alpha(INK, 0.55));
		var bw = Math.min(300, w - 40), top = h * 0.42;
		button(c, x - bw / 2, top, bw, 86, "A  LIGHT", "ROUTE THE MOTH'S LIGHT", 0xFFFFE9B0, () -> choose("a"));
		button(c, x - bw / 2, top + 104, bw, 86, "B  WAY", "OPEN THE MOTH'S WAY", 0xFF9FCBE0, () -> choose("b"));
		button(c, x - 80, top + 226, 160, 38, "THE OLD GAME", "", alpha(INK, 0.5), () -> choose("game"));
	}

	function button(c:Painter, x:Float, y:Float, w:Float, h:Float, label:String, sub:String, color:Int, act:() -> Void) {
		box(c, x, y, w, h, 0xFF1A1D2C, 10);
		outline(c, x, y, w, h, 1.5, alpha(color, 0.6), 10);
		var size = h > 60 ? 22 : 11;
		text(c, label, x + w / 2, y + h / 2 - (sub == "" ? 0 : 9), size, color);
		if (sub != "") text(c, sub, x + w / 2, y + h / 2 + 20, 9, alpha(INK, 0.6));
		buttons.push({x: x, y: y, w: w, h: h, act: act});
	}

	function game(c:Painter, w:Float, h:Float) {
		var p = play;
		if (p == null) return;
		var v = view(w, h, p.board.cols, p.board.rows);
		c.save();
		c.transform(v.s, 0, 0, -v.s, v.x, v.y + p.board.rows * v.s);
		p.draw(c, time);
		c.restore();
		// (the bar: back to the title, the screen, again)
		small(c, 12, 12, 76, 32, "< MENU", () -> {
			proto = "";
			play = null;
		});
		small(c, w - 88, 12, 76, 32, "RESET", () -> start(index));
		text(c, '${proto.toUpperCase()}${index + 1}/${screens()}', w / 2, 22, 10, alpha(INK, 0.5));
		text(c, name(), w / 2, 40, 12, INK);
		if (p.solved) {
			var last = index == screens() - 1;
			var y = h - FOOT / 2;
			text(c, last ? "ALL SOLVED" : "SOLVED", w / 2, y - 2, 14, 0xFFFFE9B0);
			if (!last) small(c, w - 100, h - FOOT + 4, 88, 32, "NEXT >", () -> start(index + 1));
		} else text(c, hint(), w / 2, h - FOOT / 2, 9, alpha(INK, 0.55));
		if (fade > 0) box(c, 0, 0, w, h, alpha(BACK, fade));
	}

	function small(c:Painter, x:Float, y:Float, w:Float, h:Float, label:String, act:() -> Void) {
		box(c, x, y, w, h, 0xFF1A1D2C, 8);
		outline(c, x, y, w, h, 1, alpha(INK, 0.3), 8);
		text(c, label, x + w / 2, y + h / 2, 10, alpha(INK, 0.85));
		buttons.push({x: x, y: y, w: w, h: h, act: act});
	}

	// the board in the window: as large as fits between the bar and the hint
	static function view(w:Float, h:Float, cols:Int, rows:Int) {
		var s = Math.min((w - EDGE * 2) / cols, (h - BAR - FOOT - EDGE) / rows);
		return {s: s, x: (w - cols * s) / 2, y: BAR + (h - BAR - FOOT - rows * s) / 2};
	}

	function world(px:Float, py:Float) {
		var p = play, s = window.scale;
		if (p == null) return {x: 0.0, y: 0.0};
		var v = view(device.width / s, device.height / s, p.board.cols, p.board.rows);
		return {x: (px / s - v.x) / v.s, y: p.board.rows - (py / s - v.y) / v.s};
	}

	// ---- input (pixels)

	public function event(e:Event) {
		if (proto == "game") {
			var o = old;
			if (o == null) return;
			switch e.kind {
				case KeyDown if (e.key == 0xFF1B): proto = "";
				case KeyDown if (e.key >= "1".code && e.key <= "3".code): o.game.start(e.key - "1".code);
				case PointerDown if (e.pointer.primary || e.pointer.buttons & 1 != 0):
					var at = o.aim(e.x, e.y - lift(e.pointer));
					o.game.press(at.x, at.y);
				case PointerMove if (e.pointer.down):
					var at = o.aim(e.x, e.y - lift(e.pointer));
					o.game.drag(at.x, at.y);
				case PointerUp | PointerCancel: o.game.release();
				case _:
			}
			return;
		}
		switch e.kind {
			case KeyDown if (e.key == 0xFF1B):
				if (play == null) window.close() else {
					proto = "";
					play = null;
				}
			case KeyDown if (play == null && (e.key == "a".code || e.key == "b".code)): choose(String.fromCharCode(e.key));
			case KeyDown if (play != null && e.key >= "1".code && e.key <= "9".code && e.key - "1".code < screens()): start(e.key - "1".code);
			case KeyDown if (play != null && e.key == "r".code): start(index);
			case PointerDown if (e.pointer.primary || e.pointer.buttons & 1 != 0):
				var s = window.scale, x = e.x / s, y = e.y / s;
				for (b in buttons)
					if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
						b.act();
						return;
					}
				var p = play;
				if (p == null || leaving) return;
				var at = world(e.x, e.y);
				touched = true;
				p.down(at.x, at.y);
			case PointerMove if (e.pointer.down && touched):
				var p = play;
				var at = world(e.x, e.y);
				if (p != null) p.move(at.x, at.y);
			case PointerUp | PointerCancel if (touched):
				touched = false;
				var p = play;
				if (p != null) p.up();
			case _:
		}
	}

	static inline function lift(p:Pointer):Float
		return Afterglow.lift(p);
}
