import helder.ui.*;
import helder.ui.widgets.Theme;

// A cell's moment of light after an agent changed its glyph: a soft violet
// glow that comes up quickly and fades, and a few specks rising from the
// letter and going out; drawn only while one is under way (Workshop.touched).
class Glimmer extends Node {
	static inline var LENGTH = 1.4;

	final ws:Workshop;
	final char:String;
	var seen = 0;
	var start = 0.0;

	public function new(ws:Workshop, char:String) {
		super("glimmer");
		this.ws = ws;
		this.char = char;
		style.position = Absolute;
		style.inset = 0;
		style.pointerEvents = None;
	}

	public function wake()
		if (ui != null) ui.requestFrame();

	override public function hasContent():Bool
		return true;

	override public function paintContent(c:Canvas, x:Float, y:Float, w:Float, h:Float) {
		var touch = ws.touched.peek().get(char);
		if (touch == null) return;
		// (a change seen for the first time: its glow starts now, after its place in the wave)
		if (touch.change != seen) {
			seen = touch.change;
			start = Clock.now + touch.delay;
		}
		var at = start, age = Clock.now - at;
		if (age > LENGTH) return;
		// (not yet its turn in a wave: wait for it)
		if (ui != null) ui.requestFrame();
		if (age < 0) return;
		var violet = Theme.c("violet"), t = age / LENGTH;
		var glow = age < 0.15 ? age / 0.15 : Math.pow(1 - (age - 0.15) / (LENGTH - 0.15), 1.6);
		c.shadow(x, y, w, h, Theme.RADIUS_M, alpha(violet, 0.35 * glow), 14);
		c.rect(x, y, w, h, Theme.RADIUS_M, alpha(violet, 0.05 * glow), 1, alpha(violet, 0.45 * glow));
		// (the specks: each from a place of its own along the letter, rising and going out)
		for (k in 0...6) {
			var start = k * 0.08, life = (age - start) / 0.9;
			if (life < 0 || life > 1) continue;
			var seed = k * 7919 + Std.int(at * 1000);
			var sx = x + w * (0.2 + 0.6 * rand(seed)), sy = y + h * (0.35 + 0.35 * rand(seed + 1));
			var px = sx + (rand(seed + 2) - 0.5) * 10 * life, py = sy - 18 * life;
			var r = (1 - life) * (1.2 + rand(seed + 3) * 1.6);
			c.rect(px - r, py - r, r * 2, r * 2, r, alpha(Color.mix(violet, 0xFFFFFFFF, 0.4), (1 - life) * 0.9), 0, 0);
		}
	}

	static function rand(n:Int):Float {
		var h = n * 0x45d9f3b;
		h = (h ^ (h >>> 16)) * 0x45d9f3b;
		return ((h ^ (h >>> 16)) & 0xFFFFFF) / 0xFFFFFF;
	}

	static inline function alpha(c:Color, a:Float):Color
		return Color.rgba((c : Int) & 0xFFFFFF, ((c : Int) >>> 24) / 255 * a);
}
