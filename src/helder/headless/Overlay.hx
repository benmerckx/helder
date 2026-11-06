package helder.headless;

import haxe.io.Bytes;
import helder.canvas.*;
import helder.text.*;

using StringTools;

// What a headless run draws over its frames for a screencast (--keys,
// --pointer), after the program's frame and on the CPU (helder.canvas), so
// it is in the PNGs and the video but never in --tree or --trace:
// keycaps, the script's keys as they are pressed (typing within a second
// one cap, a key pressed again within a second counted: ↓ ×3; modifiers
// as ⌃⌥⇧⌘, named keys as glyphs), each springing in and fading out 1.5 s
// after its last key, three at most, in a corner (bottom-left by default);
// and a ripple at each press. One fixed style, light or dark (keysTheme;
// the run's theme by default), whatever the program's look.
class Overlay {
	static inline var SHOWN = 1.5;
	static inline var FADE = 0.25;
	static inline var JOIN = 1.0;

	final corner:Null<String>;
	final light:Bool;
	final pointer:Bool;
	final caps:Array<{start:Float, last:Float, text:String, typed:Bool, count:Int, label:String}> = [];
	final presses:Array<{t:Float, x:Float, y:Float}> = [];
	var fonts:Null<FontSet> = null;
	var fontSize = 0.0;

	public function new(corner:Null<String>, theme:String, pointer:Bool) {
		this.corner = corner;
		if (corner != null && !["bottom-left", "bottom", "bottom-right", "top-left", "top", "top-right"].contains(corner))
			throw 'helder headless: --keys-at $corner: bottom-left, bottom, bottom-right, top-left, top or top-right';
		light = theme != "dark";
		this.pointer = pointer;
	}

	// a key at t: typed (a character of type) joins the cap before it when within a second
	public function key(t:Float, label:String, typed:Bool) {
		if (corner == null) return;
		var c = caps.length > 0 ? caps[caps.length - 1] : null;
		if (c != null && t - c.last <= JOIN) {
			if (typed && c.typed) {
				c.text += label;
				c.label = c.text;
				c.last = t;
				return;
			}
			if (!typed && !c.typed && c.text == label) {
				c.count++;
				c.label = c.text + " ×" + c.count;
				c.last = t;
				return;
			}
		}
		caps.push({start: t, last: t, text: label, typed: typed, count: 1, label: label});
	}

	public function press(t:Float, x:Float, y:Float)
		if (pointer) presses.push({t: t, x: x, y: y});

	// over rgba (straight, w x h pixels, scale pixels a point) at time t
	public function draw(rgba:Bytes, w:Int, h:Int, scale:Float, t:Float, dark:Bool) {
		var canvas = new Canvas(w, h);
		canvas.writePixels(rgba, 0, 0, w, h);
		canvas.scale(scale, scale);
		var pw = w / scale, ph = h / scale;
		for (p in presses) {
			var k = (t - p.t) / 0.45;
			if (k < 0 || k > 1) continue;
			var e = 1 - (1 - k) * (1 - k);
			var path = new Path();
			path.ellipse(p.x, p.y, 8 + 22 * e, 8 + 22 * e, 0, 0, Math.PI * 2);
			canvas.fill(path, Paint.solid(argb(0x3B82F6, 0.35 * (1 - k))));
			var ring = new Stroke(2);
			canvas.stroke(path, ring, Paint.solid(argb(0x2563EB, 0.8 * (1 - k))));
		}
		if (corner != null) {
			var shown = [for (c in caps) if (c.start <= t && t <= c.last + SHOWN) c];
			if (shown.length > 3) shown = shown.slice(shown.length - 3);
			var size = 16.0, pad = 10.0, gap = 8.0, margin = 16.0, hcap = size + 2 * pad;
			var top = corner.startsWith("top");
			var y = top ? margin : ph - margin - hcap;
			var i = shown.length;
			// (the newest nearest the corner's edge)
			while (--i >= 0) {
				var c = shown[i];
				var age = t - c.start, left = c.last + SHOWN - t;
				var alpha = Math.min(1, left / FADE) * Math.min(1, age / 0.12);
				var pop = age < 0.18 ? 0.85 + 0.15 * spring(age / 0.18) : 1.0;
				var layout = text(c.label, size);
				var tw = layout == null ? c.label.length * size * 0.6 : layout.width;
				var wcap = Math.max(hcap, tw + 2 * pad + 4);
				var x = corner.endsWith("left") ? margin : corner.endsWith("right") ? pw - margin - wcap : (pw - wcap) / 2;
				canvas.save();
				canvas.translate(x + wcap / 2, y + hcap / 2);
				canvas.scale(pop, pop);
				canvas.translate(-wcap / 2, -hcap / 2);
				var r = new Path();
				r.roundRect(0, 0, wcap, hcap, 8);
				canvas.fill(r, Paint.solid(argb(light ? 0xFFFFFF : 0x27272A, 0.94 * alpha)));
				canvas.stroke(r, new Stroke(1), Paint.solid(argb(light ? 0xD4D4D8 : 0x52525B, alpha)));
				if (layout != null) Glyphs.fill(canvas, layout, (wcap - tw) / 2, pad + size * 0.8, Paint.solid(argb(light ? 0x18181B : 0xFAFAFA, alpha)));
				canvas.restore();
				y += top ? hcap + gap : -(hcap + gap);
			}
		}
		canvas.readPixels(rgba, 0, 0, w, h);
	}

	// (a spring's overshoot, 0 to 1)
	static function spring(k:Float):Float
		return 1 + Math.exp(-6 * k) * Math.sin(k * Math.PI * 2.2 - Math.PI / 2) * 1.0;

	static function argb(rgb:Int, alpha:Float):Int
		return (Std.int(Math.max(0, Math.min(1, alpha)) * 255 + 0.5) << 24) | rgb;

	// (helder.text's layout of a cap's label: DejaVu Sans, else the system's sans; null: no font)
	function text(s:String, size:Float):Null<TextLayout> {
		if (fonts == null || fontSize != size) {
			var sys = SystemFonts.get();
			var face = sys.match("DejaVu Sans", 700) ?? sys.match("sans-serif", 700);
			if (face == null) return null;
			fonts = new FontSet(face, sys.fallbacks(), size);
			fontSize = size;
		}
		return new TextLayout(s, fonts, 1.2, Math.POSITIVE_INFINITY);
	}
}
