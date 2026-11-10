import Builder;
import PaintShader.sway;
import Sdf;
import Stones;
import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// The diorama: overgrown ruins over still water, built once in code
// (Stones' fields meshed by Builder) and painted by PaintShader. Near:
// roots framing the view, the moth's ledge and the wall with its glyph, a
// cliff of ledges stepping up and back; a great arch whose veins glow and
// from which lanterns hang; behind it, aqueducts in planes receding into
// the mist, each paler than the one before. The glows that light their
// surroundings are lights.
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
	// the moth's half size (its quad's): it stands 1.2 of it tall
	public static inline var MOTH = 0.45;

	public final mesh = new Builder();
	public final lights:Array<Glow> = [];
	public final beams:Array<{at:Vec4, shape:Vec4}> = [];
	public final moth:Vec3;
	public final glyph = new Vec4(-2.25, 1.85, -3.7, 0.42);
	var state = 7;

	// the index ranges: what the water mirrors, the far planes, then the
	// roots of a phone's view, then a wide one's
	public final mirrored:Int;
	public final common:Int;
	public final tall:Int;

	// (the near stone, the arch and the bridge: kept to set things on them)
	var near:Field;
	var cliff:Field;
	var arch:Field;
	var bridge:Field;

	public function new() {
		stone();
		// (standing on the ledge: its feet at the quad's 0.6 below its middle)
		moth = new Vec3(-1.3, ground(near, -1.3, -2.6, 2) + 0.6 * MOTH + 0.03, -2.6);
		great();
		growth();
		water();
		sky();
		shafts();
		mirrored = mesh.count;
		far();
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
		// the moth's ledge (its lip over the water), the wall with the
		// glyph, the ledge over it; stones fallen into the water
		var calm = [glyph.x, glyph.y, glyph.z, glyph.w * 1.5];
		var fallen = [for (k in 0...7) rock(range(-3.4, 0.9), range(-0.35, -0.05), range(-1.8, -0.9), range(0.3, 0.7), range(0, 3), k)];
		near = union([
			slab(-5.6, -1.2, -4.1, 0.15, 0.8, -1.9, 1),
			slab(-5.6, 0.55, -4.1, 0.45, 1.0, -1.5, 2, 0.7, null, 0.15),
			slab(-7, -1.2, -6.5, -1.9, 4.35, -3.7, 3, 1, calm),
			slab(-7.5, 4.2, -6.8, -1.4, 4.85, -3.3, 4),
			union(fallen, 0.05)
		], 0.1);
		b.seed = 1;
		b.field(near, -7.8, -1.0, -7.0, 1.6, 5.4, -0.4, 0.075, [1.0, 4.85], moss(1));
		// the cliff stepping up and back, under the arch's left foot
		cliff = union([
			slab(-10, -1.2, -10, -3.4, 8.3, -6.6, 5, 1.3),
			slab(-10.6, 8.1, -10.5, -2.6, 8.85, -6.1, 6),
			slab(-12, -1.2, -9, -6.5, 5.6, -5.0, 7, 1.2)
		], 0.2);
		b.seed = 5;
		b.field(cliff, -12.5, -0.6, -11, -2.0, 9.4, -4.4, 0.14, [8.85, 5.6], moss(5));
		// right: a low bridge's last bays
		bridge = arcade({x0: 0.9, x1: 9.5, z0: -10, z1: -8, y0: -1.2, spring: 1.6, r: 1.45, pier: 1.0, top: 4.3, seed: 7, broken: 0.35});
		b.seed = 7;
		b.field(bridge, 0.3, -0.6, -11, 10.2, 5.4, -7.0, 0.1, [4.66], moss(7));
		// the planes behind, each further, larger and paler
		b.seed = 8;
		b.field(arcade({x0: -7, x1: 19, z0: -17.2, z1: -15.6, y0: -1.2, spring: 3.2, r: 1.7, pier: 0.9, top: 6.4, seed: 8, broken: 0.35, wear: 0.8}), -8, -0.6, -18.5,
			20, 8.2, -14.4, 0.15, [6.8], moss(8));
	}

	// the planes far off (not in the water's mirror: the mist there hides them)
	function far() {
		var b = mesh;
		b.kind = PaintShader.STONE;
		b.seed = 9;
		b.field(union([
			arcade({x0: -30, x1: 30, z0: -27, z1: -25.5, y0: -1.2, spring: 3.4, r: 1.9, pier: 1.2, top: 6.8, seed: 9, broken: 0.25, wear: 0.6}),
			arcade({x0: -26, x1: 22, z0: -26.8, z1: -25.7, y0: 6.6, spring: 8.6, r: 1.2, pier: 0.9, top: 10.4, seed: 10, broken: 0.35, wear: 0.7})
		], 0.1), -31, -0.6, -28.5, 31, 12.2, -24.2, 0.23, [7.2, 10.8], moss(9));
		b.seed = 10;
		b.field(union([
			arcade({x0: -46, x1: 46, z0: -43, z1: -41, y0: -1.2, spring: 5.5, r: 2.8, pier: 1.8, top: 11, seed: 11, broken: 0.25, wear: 0.6}),
			arcade({x0: -40, x1: 30, z0: -42.8, z1: -41.2, y0: 10.8, spring: 13.6, r: 1.8, pier: 1.3, top: 17, seed: 12, broken: 0.3, wear: 0.6})
		], 0.2), -47, -0.6, -44.5, 47, 19, -39.5, 0.45);
		b.seed = 11;
		b.field(union([
			arcade({x0: -80, x1: 80, z0: -63, z1: -60, y0: -1.2, spring: 9, r: 4, pier: 3, top: 19, seed: 13, broken: 0.2, wear: 0.5}),
			arcade({x0: -60, x1: 50, z0: -62.6, z1: -60.4, y0: 18.8, spring: 23, r: 2.6, pier: 2.2, top: 28, seed: 14, broken: 0.3, wear: 0.5})
		], 0.3), -81, -0.6, -65, 81, 31, -58, 0.7);
		// (towers far off, between the planes, their tops broken)
		b.seed = 13;
		var towers:Array<Field> = [];
		for (k in 0...9) {
			var x = range(-42, 42), h = range(26, 52), w = range(2.2, 4.5), z = range(-76, -68);
			towers.push(tower(x, z, w, h, 20 + k));
		}
		b.field(union(towers, 0.1), -47, -0.6, -79, 47, 53, -65, 0.8);
		var mid:Array<Field> = [];
		for (k in 0...7) {
			var x = range(-28, 28), z = range(-36, -30), h = range(7, 17), w = range(1.2, 2.4);
			if (Math.abs(x) < 5) continue;
			mid.push(tower(x, z, w, h, 30 + k));
		}
		b.field(union(mid, 0.1), -30, -0.6, -37.5, 30, 18, -28.5, 0.35);
	}

	// the surface's height under (x, z), looking down from y in field f
	function ground(f:Field, x:Float, z:Float, y:Float):Float {
		while (y > -1 && f(x, y, z) > 0)
			y -= 0.02;
		return y;
	}

	// where a face of field f is, coming from (x, y) at z0 towards z1
	function face(f:Field, x:Float, y:Float, z0:Float, z1:Float):Float {
		var step = z1 > z0 ? 0.02 : -0.02, z = z0;
		while ((z1 - z) * step > 0 && f(x, y, z) > 0)
			z += step;
		return z - step;
	}

	// the roots in front: a phone's view and a wide one are framed by
	// different roots (as a stage's wings), drawn after the rest (wide: its index range)
	function roots(wide:Bool) {
		var b = mesh;
		b.kind = PaintShader.ROOT;
		b.seed = 20;
		if (!wide) {
			root([new Vec3(-3.0, -1.2, 1.2), new Vec3(-2.15, 1.2, 0.9), new Vec3(-2.4, 3.4, 0.5), new Vec3(-1.8, 5.4, 0.1), new Vec3(-2.6, 7.6, -0.4)], 0.34, 3);
			root([new Vec3(-2.7, 0.2, 1.0), new Vec3(-1.7, -0.3, 1.4), new Vec3(-0.6, -0.9, 1.8)], 0.15, 2);
			root([new Vec3(3.1, -1.2, 0.8), new Vec3(2.3, 0.8, 0.4), new Vec3(2.55, 2.6, 0.0), new Vec3(3.4, 4.6, -0.4)], 0.3, 3);
			root([new Vec3(-2.8, 6.9, 0.3), new Vec3(-1.2, 6.4, 0.0), new Vec3(0.6, 6.8, -0.2), new Vec3(2.9, 6.3, 0.1)], 0.18, 2);
			b.tube([new Vec3(-1.2, 6.4, 0.0), new Vec3(-0.9, 5.8, 0.05), new Vec3(-1.0, 5.2, 0.0)], 0.06, 0.015, 6, 5, 0.3);
			return;
		}
		root([new Vec3(-5.6, -1.5, 3), new Vec3(-3.7, 1, 2), new Vec3(-3.5, 3.8, 1.2), new Vec3(-4.7, 6.5, 0.2), new Vec3(-4.3, 10, -1)], 0.5, 3);
		root([new Vec3(-5, 0.2, 2.6), new Vec3(-2.3, -0.2, 2.4), new Vec3(0.1, -0.7, 2.8), new Vec3(2.1, -1.3, 2.4)], 0.28, 2);
		root([new Vec3(6.6, -1.2, 2.0), new Vec3(5.1, 1.4, 1.4), new Vec3(5.5, 3.8, 0.8), new Vec3(4.7, 6.8, 0.2)], 0.4, 3);
		root([new Vec3(6.6, 0.6, 2.2), new Vec3(4.7, 0.9, 1.8), new Vec3(3.3, 0.0, 2.2), new Vec3(2.3, -0.8, 2.4)], 0.2, 2);
	}

	// a root: strands twisting about a path, gnarled, thinning upwards
	function root(path:Array<Vec3>, r:Float, strands:Int) {
		var b = mesh;
		for (s in 0...strands) {
			var a = s * 2.4;
			var p = [
				for (k in 0...path.length) {
					var t = k / (path.length - 1), turn = a + t * 3.5;
					var spread = r * (0.55 + 0.4 * Math.sin(t * 5 + s));
					new Vec3(path[k].x + Math.cos(turn) * spread, path[k].y + range(-0.1, 0.1), path[k].z + Math.sin(turn) * spread * 0.7);
				}
			];
			b.seed = rand();
			var w = s == 0 ? 0.75 : range(0.4, 0.6);
			b.tube(p, r * w, r * w * 0.35, 10, 9, 0.35);
		}
	}

	function great() {
		var b = mesh;
		b.kind = PaintShader.STONE;
		b.seed = 30;
		arch = arcade({x0: -10.5, x1: 10.5, z0: -8.2, z1: -6.2, y0: -1.2, spring: 4.4, r: 7, pier: 3, top: 12.4, seed: 30, ring: true, wear: 0.8, ends: 2.5});
		b.field(arch, -11, -0.6, -9.6, 11, 15.5, -4.6, 0.14, [13.2], moss(30));
		// (glowing veins over its face, hugging it: branching from where it springs)
		b.kind = PaintShader.VEIN;
		for (start in [new Vec3(-6.4, 7.6, 0), new Vec3(-4.2, 11.0, 0), new Vec3(5.5, 9.8, 0), new Vec3(1.5, 12.0, 0), new Vec3(-8.6, 4.4, 0)])
			vein(start, rand() * Math.PI * 2, 2.2, 0.05, 3);
		// (and along the arch's edge, where a phone's view meets it)
		for (th in [0.55, 1.05, 1.45, 1.9, 2.35]) {
			var rr = range(7.4, 8.0);
			vein(new Vec3(Math.cos(th) * rr, 4.4 + Math.sin(th) * rr, 0), th + Math.PI / 2 + range(-0.5, 0.5), 1.6, 0.04, 2);
		}
		// (moss hanging under the arch, and its lanterns)
		b.kind = PaintShader.STRAND;
		for (k in 0...34) {
			var th = range(0.2, Math.PI - 0.2), z = range(-8.0, -6.4);
			// (from the intrados: march up from inside the opening to the stone)
			var x = Math.cos(th) * 6.4, yy = 4.4 + Math.sin(th) * 6.4;
			while (yy < 14 && arch(x, yy, z) > 0) {
				x += Math.cos(th) * 0.03;
				yy += Math.sin(th) * 0.03;
			}
			var len = range(0.3, 2.6) * (0.4 + Math.sin(th));
			strand(new Vec3(x, yy + 0.02, z), len);
		}
		// (long vines hanging from the crown, dark against the mist)
		b.kind = PaintShader.ROOT;
		for (v in [[-3.4, 5.5], [-0.2, 7.0], [4.2, 4.6], [5.8, 6.2], [-5.6, 3.2]]) {
			var x = v[0], z = range(-7.8, -6.6), y = 4.4 + Math.sqrt(Math.max(49 - x * x, 0));
			while (y < 14 && arch(x, y, z) > 0)
				y += 0.03;
			var top = new Vec3(x, y, z), len = v[1];
			b.anchor = top;
			b.sway = 0.03;
			b.seed = rand();
			b.tube([top, new Vec3(x + range(-0.3, 0.3), y - len * 0.4, z), new Vec3(x + range(-0.4, 0.4), y - len * 0.75, z + 0.2), new Vec3(x + range(-0.3, 0.3), y - len, z)], 0.07, 0.025, 8, 5, 0.4);
			b.sway = 0;
		}
		lantern(new Vec3(-1.1, 11.2, -7.0), 3.6, 0.1);
		lantern(new Vec3(1.3, 11.2, -7.6), 2.4, 0.4);
		lantern(new Vec3(2.9, 11.0, -6.8), 4.4, 0.7);
		for (p in [new Vec3(-5.6, 9, -5.6), new Vec3(4.8, 10.8, -5.6), new Vec3(0, 12.6, -5.5)])
			lights.push({pos: p, radius: 4.5, color: PaintShader.acid(), power: 0.7});
	}

	// moss over a ledge's edge from (x0, z0) to (x1, z1) at height y, on
	// field f: strands hanging from where its face is (out: the face's normal)
	function edge(f:Field, x0:Float, z0:Float, x1:Float, z1:Float, y:Float, density = 1.0) {
		var b = mesh;
		var len = Math.sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
		var nx = (z1 - z0) / len, nz = -(x1 - x0) / len;
		if (nz < 0 || (nz == 0 && nx < 0)) {
			nx = -nx;
			nz = -nz;
		}
		b.kind = PaintShader.STRAND;
		var m = Std.int(len * 5 * density);
		for (k in 0...m) {
			var t = rand();
			var x = x0 + (x1 - x0) * t + nx * 0.8, z = z0 + (z1 - z0) * t + nz * 0.8;
			var h = y - range(0.05, 0.2);
			// (in along the normal to the face)
			var s = 0.0;
			while (s < 1.6 && f(x - nx * s, h, z - nz * s) > 0)
				s += 0.02;
			if (s >= 1.6) continue;
			strand(new Vec3(x - nx * (s - 0.03), h + 0.04, z - nz * (s - 0.03)), Math.pow(rand(), 2.2) * 1.2 + 0.1);
		}
	}

	function vein(p:Vec3, a:Float, len:Float, r:Float, depth:Int) {
		var points = [p];
		var at = p;
		for (k in 0...4) {
			a += range(-0.6, 0.6);
			at = new Vec3(at.x + Math.cos(a) * len / 4, at.y + Math.sin(a) * len / 4, 0);
			points.push(at);
		}
		var hugged = [for (q in points) new Vec3(q.x, q.y, face(arch, q.x, q.y, -5.0, -8.2) + 0.02)];
		// (only where there is stone to grow on)
		for (q in hugged)
			if (q.z < -8.0) return;
		mesh.extra = depth / 3;
		mesh.seed = rand();
		mesh.tube(hugged, r, r * 0.3, 4, 4);
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
		b.tube([top, new Vec3(top.x + bend, top.y - len * 0.5, top.z), new Vec3(top.x + bend * 2.5, top.y - len, top.z + bend)], range(0.01, 0.024), 0.006, 4, 3);
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
		b.tube([new Vec3(base.x, base.y - 0.05, base.z), new Vec3(base.x + lean * 0.3, base.y + height * 0.5, base.z), tip], cap * 0.16, cap * 0.12, 3, 5);
		b.kind = PaintShader.CAP;
		b.lathe(tip, [0.0, cap * 0.32, cap * 0.55, cap * 0.26, cap * 0.92, cap * 0.08, cap, -0.02 * cap, cap * 0.7, -0.03 * cap, 0.0, 0.0], 12);
	}

	// caps on field f about (x, z), each where the ground is
	function caps(f:Field, x:Float, z:Float, y:Float, spread:Float, count:Int, size:Float, acid:Bool) {
		for (k in 0...count) {
			var px = x + range(-spread, spread), pz = z + range(-spread, spread) * 0.6;
			var g = ground(f, px, pz, y + 0.6);
			if (g < y - 0.6) continue;
			mushroom(new Vec3(px, g, pz), range(0.4, 1.0) * size * 2, range(0.5, 1.0) * size, acid, range(-0.05, 0.05));
		}
	}

	function sprouts(f:Field, c:Vec3, spread:Float, count:Int) {
		var b = mesh;
		for (k in 0...count) {
			var x = c.x + range(-spread, spread), z = c.z + range(-spread, spread) * 0.6;
			var y = ground(f, x, z, c.y + 0.6);
			if (y < c.y - 0.6) continue;
			var base = new Vec3(x, y - 0.02, z);
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
		edge(near, -5.5, -1.5, 0.4, -1.5, 1.0);
		edge(near, 0.4, -1.5, 0.4, -4.0, 1.0, 0.7);
		edge(near, -7.5, -3.3, -1.4, -3.3, 4.85);
		edge(near, -1.4, -3.3, -1.4, -6.8, 4.85, 0.6);
		edge(cliff, -10.6, -6.1, -2.6, -6.1, 8.85);
		edge(cliff, -12, -5.0, -6.5, -5.0, 5.6, 0.6);
		edge(bridge, 0.75, -7.6, 9.65, -7.6, 4.66, 0.8);
		// (cyan caps by the moth, on the ledge's far side)
		caps(near, -3.9, -2.5, 1.0, 0.5, 7, 0.13, false);
		lights.push({pos: new Vec3(-3.9, 1.4, -2.4), radius: 2.6, color: PaintShader.cyan(), power: 1.6});
		// (acid shelves out of the wall above it)
		for (s in [new Vec3(-2.3, 3.2, 0), new Vec3(-2.0, 3.7, 0), new Vec3(-2.6, 2.7, 0)]) {
			var z = face(near, s.x - 0.3, s.y - 0.25, -2.5, -4.5);
			mushroom(new Vec3(s.x - 0.3, s.y - 0.25, z - 0.05), 0.25, range(0.28, 0.42), true, 0.3);
		}
		lights.push({pos: new Vec3(-1.9, 3.5, -3.0), radius: 2.8, color: PaintShader.acid(), power: 1.4});
		// (cyan on the bridge to the right, on the arcade behind)
		caps(bridge, 3.9, -9.0, 4.66, 1.3, 8, 0.16, false);
		lights.push({pos: new Vec3(3.9, 5.1, -8.8), radius: 3.2, color: PaintShader.cyan(), power: 1.5});
		caps(cliff, -4.6, -7.0, 8.85, 1.3, 5, 0.2, true);
		lights.push({pos: new Vec3(-4.6, 9.2, -6.6), radius: 3.5, color: PaintShader.acid(), power: 1.1});
		// (magenta sprouts)
		sprouts(near, new Vec3(-2.0, 1.0, -2.0), 0.45, 9);
		sprouts(near, new Vec3(-4.6, 4.85, -3.6), 0.5, 8);
		sprouts(bridge, new Vec3(6.6, 4.66, -8.6), 0.6, 9);
		sprouts(cliff, new Vec3(-5.6, 8.85, -6.4), 0.6, 7);
		// (on the rubble by the bridge's foot, over the water)
		caps(bridge, 2.3, -7.0, 0.3, 0.5, 5, 0.1, false);
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

	// shafts of light through the mist, between the planes (x, z, width, height, strength)
	function shafts() {
		for (s in [
			[-2.6, -12, 1.0, 15, 0.8], [3.2, -21, 1.8, 20, 1.0], [-5.5, -22, 1.2, 18, 0.7], [7.5, -33, 2.6, 26, 0.9], [-0.5, -36, 2.0, 26, 1.1],
			[-12, -38, 3.0, 28, 0.7], [12, -52, 4.0, 34, 0.8], [-6, -55, 3.5, 34, 0.9], [2, -12.5, 0.6, 12, 0.5]
		])
			beams.push({at: new Vec4(s[0], -0.5, s[1], s[2]), shape: new Vec4(s[3], -0.18, rand(), s[4])});
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
