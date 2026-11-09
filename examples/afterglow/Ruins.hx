import Builder;
import PaintShader.sway;
import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// The diorama: overgrown ruins over still water, built once in code
// (Builder) and painted by PaintShader. Near: roots framing the view, the
// moth's ledge and the wall with its glyph; under a great arch whose
// veins glow and from which lanterns hang; behind, arcades fading into
// the mist. The glows that light their surroundings are lights.
typedef Glow = {
	var pos:Vec3;
	var radius:Float;
	var color:Vec3;
	var power:Float;
	var ?anchor:Vec4;
	var ?seed:Float;
}

class Ruins {
	public static inline var MAX_LIGHTS = 32;

	public final mesh = new Builder();
	public final lights:Array<Glow> = [];
	public final moth = new Vec3(-0.9, 1.22, -2.5);
	public final glyph = new Vec4(-2.75, 2.15, -3.7, 0.55);
	var state = 7;

	// the index ranges: the ruins, then the roots of a phone's view, then a wide one's
	public final common:Int;
	public final tall:Int;

	public function new() {
		stone();
		arch();
		growth();
		water();
		sky();
		common = mesh.count;
		roots(false);
		tall = mesh.count;
		roots(true);
	}

	function rand():Float {
		state = (state * 1103515245 + 12345) & 0x7fffffff;
		return state / 0x7fffffff;
	}

	inline function range(a:Float, b:Float)
		return a + (b - a) * rand();

	function stone() {
		var b = mesh;
		b.kind = PaintShader.STONE;
		// the moth's ledge and the wall behind it (the glyph on its face)
		b.seed = 1;
		b.boxes(-5.5, -1, -4.0, 0.2, 1.0, -1.7);
		b.seed = 2;
		b.boxes(-7, -1, -6.5, -1.9, 4.3, -3.7);
		b.seed = 3;
		b.boxes(-7.5, 4.3, -6.8, -1.5, 4.85, -3.35);
		b.seed = 4;
		b.boxes(-10, -1, -10, -3.2, 8.3, -6.6);
		b.seed = 5;
		b.boxes(-10.5, 8.3, -10.4, -2.7, 8.8, -6.2);
		// (the ledge's broken lip, fallen blocks in the water)
		b.seed = 6;
		for (k in 0...7) {
			var x = range(-3.2, 0.4), z = range(-2.3, -1.4);
			var s = range(0.25, 0.6);
			b.box(new Vec3(x, range(-0.3, 0.05), z), new Vec3(s, s * 0.8, s), range(0, 3));
		}
		b.box(new Vec3(0.25, 0.75, -2.2), new Vec3(0.7, 0.5, 0.8), 0.3);
		b.box(new Vec3(-0.3, 1.05, -3.2), new Vec3(0.5, 0.25, 0.6), 0.6);
		// right: an arcade's last bays, and a taller one behind
		b.seed = 7;
		b.arcade(0.9, 9.5, -10, -8, -1, 1.6, 1.5, 1.1, 4.3);
		b.seed = 8;
		b.arcade(5.5, 18, -17, -15, -1, 3.4, 1.9, 1.4, 7.6);
		for (k in 0...6) {
			var x = range(1.5, 6), z = range(-7.5, -5.5), s = range(0.3, 0.8);
			b.box(new Vec3(x, range(-0.4, 0), z), new Vec3(s, s * 0.7, s * 1.2), range(0, 3));
		}
		// the far arcades, tiers of them
		b.seed = 9;
		b.arcade(-34, 34, -27, -25, -1, 2.8, 1.8, 1.3, 6.4);
		b.arcade(-34, 34, -27, -25, 6.75, 8.4, 1.2, 1.0, 10.2);
		b.seed = 10;
		b.arcade(-48, 48, -42, -40, -1, 5, 2.8, 2, 11);
		b.arcade(-48, 48, -42, -40, 11.4, 13.5, 1.8, 1.4, 17);
		b.seed = 11;
		b.arcade(-80, 80, -62, -59, -1, 9, 4, 3, 19);
		b.arcade(-80, 80, -62, -59, 19.5, 22.5, 2.6, 2.2, 28);
		// (spires far off, dark in the mist)
		b.seed = 13;
		for (k in 0...9) {
			var x = range(-45, 45), h = range(30, 60), w = range(2, 5);
			b.box(new Vec3(x, h / 2 - 1, range(-75, -66)), new Vec3(w, h, w), range(0, 1));
			b.box(new Vec3(x, h - 1, range(-75, -66)), new Vec3(w * 1.6, 1.2, w * 1.6), 0);
		}
		// (broken towers between the tiers)
		b.seed = 12;
		for (k in 0...7) {
			var x = range(-30, 30), z = range(-36, -20), h = range(6, 16), w = range(1.2, 2.6);
			if (Math.abs(x) < 4) continue;
			b.box(new Vec3(x, h / 2 - 1, z), new Vec3(w, h, w), range(0, 1));
		}
	}

	// the roots in front: a phone's view and a wide one are framed by
	// different roots (as a stage's wings), drawn after the rest (wide: its index range)
	function roots(wide:Bool) {
		var b = mesh;
		b.kind = PaintShader.ROOT;
		b.seed = 20;
		if (!wide) {
			b.tube([new Vec3(-2.9, -1.2, 1.2), new Vec3(-2.1, 1.2, 0.9), new Vec3(-2.35, 3.4, 0.5), new Vec3(-1.75, 5.4, 0.1), new Vec3(-2.5, 7.6, -0.4)], 0.36, 0.16, 10, 9);
			b.tube([new Vec3(-2.6, 0.2, 1.0), new Vec3(-1.6, -0.3, 1.4), new Vec3(-0.6, -0.9, 1.8)], 0.16, 0.05, 8, 6);
			b.tube([new Vec3(3.0, -1.2, 0.8), new Vec3(2.25, 0.8, 0.4), new Vec3(2.5, 2.6, 0.0), new Vec3(3.4, 4.6, -0.4)], 0.32, 0.14, 10, 8);
			b.tube([new Vec3(-2.8, 6.9, 0.3), new Vec3(-1.2, 6.3, 0.0), new Vec3(0.6, 6.7, -0.2), new Vec3(2.8, 6.2, 0.1)], 0.2, 0.08, 10, 7);
			b.tube([new Vec3(-1.2, 6.3, 0.0), new Vec3(-0.9, 5.7, 0.05), new Vec3(-1.0, 5.2, 0.0)], 0.06, 0.015, 6, 5);
			return;
		}
		b.tube([new Vec3(-5.5, -1.5, 3), new Vec3(-3.6, 1, 2), new Vec3(-3.4, 3.8, 1.2), new Vec3(-4.6, 6.5, 0.2), new Vec3(-4.2, 10, -1)], 0.55, 0.25, 8, 9);
		b.tube([new Vec3(-5, 0.2, 2.6), new Vec3(-2.2, -0.2, 2.4), new Vec3(0.2, -0.7, 2.8), new Vec3(2.2, -1.3, 2.4)], 0.32, 0.12, 8, 7);
		b.tube([new Vec3(6.5, -1.2, 2.0), new Vec3(5.0, 1.4, 1.4), new Vec3(5.4, 3.8, 0.8), new Vec3(4.6, 6.8, 0.2)], 0.42, 0.2, 10, 8);
		b.tube([new Vec3(6.5, 0.6, 2.2), new Vec3(4.6, 0.9, 1.8), new Vec3(3.2, 0.0, 2.2), new Vec3(2.2, -0.8, 2.4)], 0.22, 0.08, 8, 6);
	}

	function arch() {
		var b = mesh;
		b.kind = PaintShader.STONE;
		b.seed = 30;
		b.arcade(-10, 10, -8.2, -6.2, -1, 4.4, 7, 3, 12.6, 0.6);
		// (glowing veins over its face: branching from where it springs)
		b.kind = PaintShader.VEIN;
		for (start in [new Vec3(-6.4, 7.6, -6.15), new Vec3(-4.2, 11.4, -6.15), new Vec3(5.5, 9.8, -6.15), new Vec3(1.5, 12.2, -6.15)])
			vein(start, rand() * Math.PI * 2, 2.2, 0.045, 3);
		// (and along the arch's edge, where a phone's view meets it)
		for (th in [0.55, 1.05, 1.45, 1.9, 2.35]) {
			var rr = range(7.3, 7.9);
			vein(new Vec3(Math.cos(th) * rr, 4.4 + Math.sin(th) * rr, -6.15), th + Math.PI / 2 + range(-0.5, 0.5), 1.6, 0.035, 2);
		}
		// (moss hanging under the arch, and its lanterns)
		b.kind = PaintShader.STRAND;
		for (k in 0...26) {
			var th = range(0.2, Math.PI - 0.2), x = Math.cos(th) * 7, y = 4.4 + Math.sin(th) * 7;
			var z = range(-8.1, -6.3), len = range(0.3, 2.4) * (0.4 + Math.sin(th));
			strand(new Vec3(x, y + 0.05, z), len);
		}
		for (k in 0...14) {
			var x = range(-8, 8), z = -6.15;
			strand(new Vec3(x, 12.6, z), range(0.3, 1.6));
		}
		lantern(new Vec3(-1.1, 11.35, -7.0), 3.6, 0.1);
		lantern(new Vec3(1.3, 11.35, -7.6), 2.4, 0.4);
		lantern(new Vec3(2.9, 11.2, -6.8), 4.4, 0.7);
		for (p in [new Vec3(-5.6, 9, -5.6), new Vec3(4.8, 10.8, -5.6), new Vec3(0, 12.8, -5.5)])
			lights.push({pos: p, radius: 4.5, color: PaintShader.acid(), power: 0.7});
	}

	// fallen and loose stones along an edge from (x0, z0) to (x1, z1) on top at y: a broken skyline
	function crumble(x0:Float, z0:Float, x1:Float, z1:Float, y:Float, size = 1.0) {
		var b = mesh;
		var len = Math.sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
		var n = Std.int(len * 1.4);
		b.kind = PaintShader.STONE;
		for (k in 0...n) {
			if (rand() < 0.35) continue;
			var f = rand(), s = range(0.2, 0.55) * size;
			b.seed = rand() * 10;
			b.box(new Vec3(x0 + (x1 - x0) * f + range(-0.2, 0.2), y + s * range(0.1, 0.4), z0 + (z1 - z0) * f + range(-0.3, 0.1)),
				new Vec3(s * range(1, 1.8), s * range(0.5, 1.0), s), range(-0.4, 0.4));
		}
	}

	// moss over a ledge's edge from (x0, z0) to (x1, z1) at height y:
	// lumps on it, strands hanging from it
	function edge(x0:Float, z0:Float, x1:Float, z1:Float, y:Float, density = 1.0) {
		var b = mesh;
		var len = Math.sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
		var yaw = Math.atan2(-(z1 - z0), x1 - x0);
		var n = Std.int(len * 2.2 * density);
		b.kind = PaintShader.MOSS;
		for (k in 0...n) {
			var f = (k + rand()) / n;
			var w = range(0.25, 0.7);
			b.seed = rand();
			b.box(new Vec3(x0 + (x1 - x0) * f, y + range(-0.02, 0.05), z0 + (z1 - z0) * f), new Vec3(w, range(0.08, 0.18), range(0.2, 0.4)), yaw + range(-0.3, 0.3));
		}
		b.kind = PaintShader.STRAND;
		var m = Std.int(len * 4 * density);
		for (k in 0...m) {
			var f = rand();
			var nx = Math.sin(yaw), nz = Math.cos(yaw);
			strand(new Vec3(x0 + (x1 - x0) * f + nx * 0.12, y + 0.02, z0 + (z1 - z0) * f + nz * 0.12), Math.pow(rand(), 2.2) * 1.1 + 0.08);
		}
	}

	function vein(p:Vec3, a:Float, len:Float, r:Float, depth:Int) {
		var points = [p];
		var at = p;
		for (k in 0...4) {
			a += range(-0.6, 0.6);
			at = new Vec3(at.x + Math.cos(a) * len / 4, at.y + Math.sin(a) * len / 4, at.z);
			points.push(at);
		}
		mesh.extra = depth / 3;
		mesh.seed = rand();
		mesh.tube(points, r, r * 0.3, 4, 4);
		if (depth > 0)
			for (k in 0...2) {
				var i = 1 + Std.int(rand() * 3);
				vein(points[i], a + (k == 0 ? 0.8 : -0.8) + range(-0.3, 0.3), len * 0.6, r * 0.6, depth - 1);
			}
	}

	function strand(top:Vec3, len:Float) {
		var b = mesh;
		b.anchor = top;
		b.sway = 0.04;
		b.seed = rand();
		b.extra = rand() < 0.3 ? 1 : 0.1;
		var bend = range(-0.08, 0.08);
		b.tube([top, new Vec3(top.x + bend, top.y - len * 0.5, top.z), new Vec3(top.x + bend * 2.5, top.y - len, top.z + bend)], range(0.02, 0.045), 0.01, 4, 4);
		b.sway = 0;
	}

	function lantern(hook:Vec3, drop:Float, seed:Float) {
		var b = mesh;
		var c = new Vec3(hook.x, hook.y - drop, hook.z);
		var anchor = new Vec4(hook.x, hook.y, hook.z, 0.07);
		b.anchor = hook;
		b.sway = anchor.w;
		b.seed = seed;
		b.kind = PaintShader.ROOT;
		b.tube([hook, new Vec3(c.x, c.y + 0.55, c.z)], 0.02, 0.02, 2, 4);
		b.kind = PaintShader.CAGE;
		b.lathe(c, [0.0, 0.62, 0.08, 0.55, 0.22, 0.32, 0.27, 0.0, 0.22, -0.3, 0.08, -0.55, 0.0, -0.66], 14, true);
		b.kind = PaintShader.CORE;
		b.lathe(c, [0.0, 0.14, 0.07, 0.11, 0.1, 0.0, 0.07, -0.11, 0.0, -0.14], 8);
		b.sway = 0;
		lights.push({pos: c, radius: 4.5, color: PaintShader.magenta(), power: 3.2, anchor: anchor, seed: seed});
	}

	function mushroom(base:Vec3, height:Float, cap:Float, acid:Bool, lean = 0.0) {
		var b = mesh;
		b.extra = acid ? 1 : 0;
		b.seed = rand();
		var tip = new Vec3(base.x + lean, base.y + height, base.z);
		b.kind = PaintShader.STEM;
		b.tube([base, new Vec3(base.x + lean * 0.3, base.y + height * 0.5, base.z), tip], cap * 0.16, cap * 0.12, 3, 5);
		b.kind = PaintShader.CAP;
		b.lathe(tip, [0.0, cap * 0.32, cap * 0.55, cap * 0.26, cap * 0.92, cap * 0.08, cap, -0.02 * cap, cap * 0.7, -0.03 * cap, 0.0, 0.0], 12);
	}

	function sprouts(c:Vec3, spread:Float, count:Int) {
		var b = mesh;
		for (k in 0...count) {
			var base = new Vec3(c.x + range(-spread, spread), c.y, c.z + range(-spread, spread) * 0.6);
			var h = range(0.08, 0.26), tip = new Vec3(base.x + range(-0.04, 0.04), base.y + h, base.z);
			b.seed = rand();
			b.extra = 0;
			b.kind = PaintShader.STEM;
			b.tube([base, tip], 0.008, 0.006, 2, 3);
			b.kind = PaintShader.BULB;
			var r = range(0.018, 0.035);
			b.lathe(tip, [0.0, r, r, 0.0, 0.0, -r], 6);
		}
		lights.push({pos: new Vec3(c.x, c.y + 0.25, c.z), radius: 1.3, color: PaintShader.magenta(), power: 0.5});
	}

	function growth() {
		crumble(-5.5, -2.0, -2.6, -2.0, 1.0, 0.7);
		crumble(-7.5, -3.6, -1.5, -3.6, 4.85);
		crumble(-10.5, -6.5, -2.7, -6.5, 8.8);
		crumble(0.75, -8.3, 9.65, -8.3, 4.65);
		crumble(5.35, -15.3, 18.15, -15.3, 7.95, 1.4);
		crumble(-34, -25.8, 34, -25.8, 10.55, 1.8);
		crumble(-48, -40.8, 48, -40.8, 17.4, 2.5);
		crumble(-10, -7.0, 10, -7.0, 13.2, 1.6);
		edge(-5.5, -1.7, 0.2, -1.7, 1.0);
		edge(0.2, -1.7, 0.2, -4.0, 1.0, 0.7);
		edge(-7.5, -3.35, -1.5, -3.35, 4.85);
		edge(-1.5, -3.35, -1.5, -6.8, 4.85, 0.6);
		edge(-10.5, -6.2, -2.7, -6.2, 8.8);
		edge(0.75, -7.85, 9.65, -7.85, 4.65, 0.8);
		edge(5.35, -14.85, 18.15, -14.85, 7.95, 0.5);
		// (cyan caps by the moth, on the ledge's far side)
		for (k in 0...6)
			mushroom(new Vec3(-3.9 + range(-0.5, 0.5), 1.0, -2.5 + range(-0.5, 0.4)), range(0.1, 0.38), range(0.07, 0.17), false, range(-0.05, 0.05));
		lights.push({pos: new Vec3(-3.9, 1.4, -2.4), radius: 2.6, color: PaintShader.cyan(), power: 1.6});
		// (acid shelves out of the wall above it)
		var b = mesh;
		for (s in [new Vec3(-2.3, 3.1, -3.55), new Vec3(-2.0, 3.6, -3.4), new Vec3(-2.6, 2.6, -3.5)]) {
			b.extra = 1;
			mushroom(new Vec3(s.x - 0.3, s.y - 0.25, s.z - 0.1), 0.25, range(0.28, 0.42), true, 0.3);
		}
		lights.push({pos: new Vec3(-1.9, 3.4, -3.0), radius: 2.8, color: PaintShader.acid(), power: 1.4});
		// (cyan on the arcade to the right, on the towers behind)
		for (k in 0...7)
			mushroom(new Vec3(range(2.6, 5.2), 4.65, range(-9.6, -8.4)), range(0.12, 0.45), range(0.09, 0.22), false);
		lights.push({pos: new Vec3(3.9, 5.1, -8.8), radius: 3.2, color: PaintShader.cyan(), power: 1.5});
		for (k in 0...5)
			mushroom(new Vec3(range(6.5, 9.5), 8.2, range(-16.5, -15.4)), range(0.2, 0.6), range(0.15, 0.32), false);
		lights.push({pos: new Vec3(8, 8.7, -15.8), radius: 4, color: PaintShader.cyan(), power: 1.4});
		for (k in 0...4)
			mushroom(new Vec3(range(-6, -3.4), 8.8, range(-7.5, -6.5)), range(0.15, 0.4), range(0.2, 0.36), true);
		lights.push({pos: new Vec3(-4.6, 9.2, -6.6), radius: 3.5, color: PaintShader.acid(), power: 1.1});
		// (magenta sprouts)
		sprouts(new Vec3(-1.8, 1.0, -2.0), 0.45, 9);
		sprouts(new Vec3(-4.6, 4.85, -3.6), 0.5, 8);
		sprouts(new Vec3(6.6, 4.65, -8.6), 0.6, 9);
		sprouts(new Vec3(-5.6, 8.8, -6.4), 0.6, 7);
		sprouts(new Vec3(3.2, 0.35, -6.2), 0.3, 5);
		// (on the rubble by the arcade's foot, over the water)
		for (k in 0...5)
			mushroom(new Vec3(range(1.8, 2.8), 0.32, range(-7.4, -6.6)), range(0.08, 0.3), range(0.06, 0.14), false);
		lights.push({pos: new Vec3(2.3, 0.6, -7.0), radius: 2.2, color: PaintShader.cyan(), power: 1.2});
		// (moss's glow along the ledge's edge)
		lights.push({pos: new Vec3(-1.5, 0.8, -1.3), radius: 1.8, color: PaintShader.acid(), power: 0.6});
		lights.push({pos: new Vec3(4.5, 4.0, -7.6), radius: 2.2, color: PaintShader.acid(), power: 0.5});
	}

	function water() {
		var b = mesh;
		b.kind = PaintShader.PAD;
		for (k in 0...55) {
			var x = k < 15 ? range(-0.6, 2.4) : range(-1.5, 7), z = k < 15 ? range(-4.5, -0.8) : range(-16, -1.0);
			b.extra = rand() < 0.35 ? 1 : 0;
			b.seed = rand();
			b.pad(new Vec3(x, 0.012, z), range(0.12, 0.38), range(0, 6.28));
			b.extra = 0;
		}
	}

	function sky() {
		var b = mesh;
		b.kind = PaintShader.SKY;
		b.quad(new Vec3(-160, -10, -85), new Vec3(160, -10, -85), new Vec3(160, 110, -85), new Vec3(-160, 110, -85), new Vec3(0, 0, 1));
	}

	// the lights' texture: two RGBA16F texels a light (position and
	// radius, colour and power), the lanterns' swaying with them
	public function lightBytes(t:Float, into:Bytes):Int {
		var n = Std.int(Math.min(lights.length, MAX_LIGHTS));
		for (k in 0...n) {
			var l = lights[k];
			var p = l.anchor == null ? l.pos : sway(l.pos, l.anchor, t, l.seed);
			var o = k * 16;
			half(into, o, p.x);
			half(into, o + 2, p.y);
			half(into, o + 4, p.z);
			half(into, o + 6, l.radius);
			half(into, o + 8, l.color.x);
			half(into, o + 10, l.color.y);
			half(into, o + 12, l.color.z);
			half(into, o + 14, l.power);
		}
		return n;
	}

	static function half(b:Bytes, at:Int, f:Float) {
		var bits = haxe.io.FPHelper.floatToI32(f);
		var sign = (bits >>> 16) & 0x8000, exp = ((bits >>> 23) & 0xff) - 127 + 15, mant = bits & 0x7fffff;
		var h = if (exp <= 0) sign else if (exp >= 31) sign | 0x7c00 else sign | (exp << 10) | (mant >> 13);
		b.setUInt16(at, h);
	}
}
