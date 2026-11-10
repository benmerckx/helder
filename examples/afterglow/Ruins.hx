import Builder;
import Screens;
import Sdf;
import Stones;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// The diorama: overgrown ruins over still water, built once in code
// (Stones' fields meshed by Builder) and painted by PaintShader. Near:
// roots framing the view, and each screen's stone and pieces (Screens);
// a great arch over it all whose veins glow and from which lanterns hang;
// through it a cliff of ledges and a bridge's last bays; behind them the
// far ruins, planes of silhouettes receding into the mist (FarShader).
// The glows light their surroundings: summed into the vertices (bake).
typedef Glow = {
	var pos:Vec3;
	var radius:Float;
	var color:Vec3;
	var power:Float;
	var ?anchor:Vec4;
	var ?seed:Float;
}

typedef Range = {first:Int, count:Int};

// a screen as built: its stone, each piece's (as built: posed when
// drawn), and its glows
typedef Built = {mesh:Builder, stone:Range, pieces:Array<Range>, lights:Array<Glow>};

class Ruins {
	// the moth's half size (its quad's): it stands 1.2 of it tall
	public static inline var MOTH = 0.56;
	public static inline var LARVA = 0.42;

	// (the mesh being built: the common one, or a screen's while it is)
	public var mesh(default, null) = new Builder();
	public final lights:Array<Glow> = [];
	public final beams:Array<{at:Vec4, shape:Vec4}> = [];
	var state = 7;

	// the index ranges: the ruins, the roots of a phone's view, a wide one's
	public final back:Range;
	public final tall:Range;
	public final wide:Range;
	// the far planes, back to front: z, half its width, its height, then FarVertex's plane
	public final planes:Array<Array<Float>> = [
		[-78, 150, 70, 5.2, 6, 1.15, 0], [-60, 120, 52, 3.9, 5, 1.0, 0.25], [-45, 95, 40, 2.9, 4, 0.95, 0.5], [-33, 75, 30, 2.1, 3, 0.9, 0.8],
		[-24, 60, 22, 1.5, 2, 0.85, 1], [-17, 50, 15, 1.05, 1, 0.75, 1]
	];
	final screens:Array<Null<Built>> = [for (_ in Screens.all) null];

	// (the cliff, the arch and the bridge: kept to set things on them)
	var cliff:Field;
	var arch:Field;
	var bridge:Field;

	public function new() {
		stone();
		great();
		growth();
		water();
		sky();
		shafts();
		back = {first: 0, count: mesh.count};
		tall = roots(false);
		wide = roots(true);
		mesh.bake(lights);
	}

	// a screen as built: meshed the first time it is asked for (when it
	// is about to be shown, under the mist between screens), into a mesh
	// of its own, its randomness its own
	public function screen(k:Int):Built {
		if (screens[k] != null) return screens[k];
		var common = mesh, kept = state;
		mesh = new Builder();
		state = 101 + k * 977;
		var built = build(Screens.all[k], k);
		mesh = common;
		state = kept;
		return screens[k] = built;
	}

	function rand():Float {
		state = (state * 1103515245 + 12345) & 0x7fffffff;
		return state / 0x7fffffff;
	}

	inline function range(a:Float, b:Float)
		return a + (b - a) * rand();

	static inline var SPRING = 6.6;
	static inline var RADIUS = 7.6;

	function stone() {
		var b = mesh;
		b.kind = PaintShader.STONE;
		// stones fallen into the water before the ledges
		var fallen = [for (k in 0...9) rock(range(-4.4, 4.4), range(-0.35, -0.05), range(-1.2, 0.6), range(0.3, 0.7), range(0, 3), k)];
		b.seed = 1;
		b.field(union(fallen, 0.05), -5.2, -0.9, -2.0, 5.2, 0.6, 1.4, 0.09, null, moss(1));
		// through the arch, left: a cliff of ledges stepping up and back
		cliff = union([
			slab(-12, -1.2, -13.5, -3.6, 3.4, -9.8, 5, 1.2, null, 1, 5),
			slab(-12, 3.1, -14.5, -5.0, 6.9, -11.2, 6, 1.2, null, 1, 5),
			slab(-12, 6.6, -15.5, -6.4, 10.2, -12.4, 7, 1.2, null, 1, 5)
		], 0.15);
		b.seed = 5;
		b.field(cliff, -12.5, -0.6, -16, -3.0, 10.8, -9.2, 0.14, [3.4, 6.9, 10.2], moss(5));
		// right: a bridge's last bays, and a taller one behind it
		bridge = arcade({x0: 1.2, x1: 12, z0: -12.2, z1: -10.4, y0: -1.2, spring: 2.5, r: 1.55, pier: 1.1, top: 5.0, seed: 7, broken: 0.3, ends: 3.0}, 7);
		b.seed = 7;
		b.field(bridge, 0.4, -0.6, -13, 12.5, 5.6, -9.6, 0.11, [5.0], moss(7));
		var tallOne = arcade({x0: 4.2, x1: 13, z0: -15.4, z1: -14.0, y0: -1.2, spring: 7.0, r: 0.95, pier: 0.85, top: 9.4, seed: 8, broken: 0.3, ends: 2.6}, 8);
		b.seed = 8;
		b.field(tallOne, 3.6, -0.6, -16.2, 13.5, 10, -13.2, 0.14, [9.4], moss(8));
	}

	// a screen's stone, its pieces and its growth: the faces where
	// something is carved kept flat, moss over the tops and hanging from
	// the edges, caps, sprouts and shelves where it says
	function build(screen:Screen, index:Int):Built {
		var b = mesh, first = mesh.count, glows:Array<Glow> = [];
		var calm:Array<Float> = [];
		for (g in screen.glyphs)
			calm = calm.concat([g.at[0], g.at[1], g.at[2], 0.65]);
		calm = calm.concat([screen.home[0], screen.home[1] + 0.45, screen.home[2], 0.6]);
		var seed = index * 10 + 1;
		var f = union([for (k in 0...screen.stones.length) slabOf(screen.stones[k], seed + k, calm, seed)], 0.06);
		var box = bounds(screen.stones);
		b.kind = PaintShader.STONE;
		b.seed = seed;
		b.field(f, box[0], Math.max(box[1], -1.0), box[2], box[3], box[4], box[5], 0.075, [for (s in screen.stones) s.box[4]], moss(seed));
		if (screen.caps != null)
			for (c in screen.caps) {
				caps(f, c[0], c[2], c[1], c[3], Std.int(c[4]), c[5], c[6] > 0.5);
				var color = c[6] > 0.5 ? PaintShader.acid() : PaintShader.cyan();
				glows.push({pos: new Vec3(c[0], c[1] + 0.4, c[2] + 0.1), radius: 2.6, color: color, power: 1.2});
			}
		if (screen.shelves != null) {
			var at = new Vec3(0, 0, 0);
			for (s in screen.shelves) {
				var z = face(f, s[0], s[1], -1.0, -6.0);
				mushroom(new Vec3(s[0], s[1], z - 0.05), 0.25, range(0.28, 0.42), true, 0.3);
				at = at + new Vec3(s[0] + 0.4, s[1] + 0.3, z + 0.7) * (1 / screen.shelves.length);
			}
			glows.push({pos: at, radius: 2.6, color: PaintShader.acid(), power: 0.8});
		}
		if (screen.sprouts != null)
			for (s in screen.sprouts)
				glows.push(sprouts(f, new Vec3(s[0], s[1], s[2]), s[3], Std.int(s[4])));
		var stone = {first: first, count: mesh.count - first};
		var pieces:Array<Range> = [];
		for (p in screen.pieces) {
			var at = mesh.count;
			if (p.stones != null) {
				var g = union([for (k in 0...p.stones.length) slabOf(p.stones[k], seed + 5 + k, null, seed + 5, p.carries == true ? 1 : 0)], 0.05);
				var x = bounds(p.stones);
				b.kind = PaintShader.STONE;
				b.seed = seed + 5;
				b.field(g, x[0], x[1], x[2], x[3], x[4], x[5], 0.06, [for (s in p.stones) s.box[4]], moss(seed + 5));
			}
			if (p.lantern != null) {
				var l = p.lantern, hook = p.hang == null ? new Vec3(l[0], l[1] + 0.55, l[2]) : new Vec3(p.hang.at[0], p.hang.at[1], l[2]);
				b.anchor = new Vec3(0, 0, 0);
				b.sway = 0;
				b.seed = 0.3;
				cage(hook, new Vec3(l[0], l[1], l[2]), 0.3, 0.8);
			}
			pieces.push({first: at, count: mesh.count - at});
		}
		mesh.bake(lights.concat(glows));
		return {mesh: mesh, stone: stone, pieces: pieces, lights: glows};
	}

	static function slabOf(s:Stone, seed:Float, calm:Null<Array<Float>>, bs:Float, under = 1.0):Field {
		var x = s.box;
		// (only the spots on this stone's faces)
		var mine = calm == null ? null : [];
		if (calm != null) {
			var k = 0;
			while (k < calm.length) {
				if (calm[k] > x[0] - 0.7 && calm[k] < x[3] + 0.7 && calm[k + 1] > x[1] - 0.7 && calm[k + 1] < x[4] + 0.7 && calm[k + 2] > x[2] - 0.3
					&& calm[k + 2] < x[5] + 0.3) mine = mine.concat(calm.slice(k, k + 4));
				k += 4;
			}
		}
		return slab(x[0], x[1], x[2], x[3], x[4], x[5], seed, s.wear ?? 1.0, mine, s.fallen ?? 1.0, bs, s.under ?? under);
	}

	// the box about stones, with room for their wear
	static function bounds(stones:Array<Stone>):Array<Float> {
		var o = [1e9, 1e9, 1e9, -1e9, -1e9, -1e9];
		for (s in stones)
			for (k in 0...3) {
				o[k] = Math.min(o[k], s.box[k] - 0.4);
				o[k + 3] = Math.max(o[k + 3], s.box[k + 3] + 0.4);
			}
		return o;
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
	// different roots (as a stage's wings), rising out of the water in the
	// corners and up the sides (wide: its index range)
	function roots(wide:Bool):Range {
		var b = mesh, first = mesh.count;
		b.kind = PaintShader.ROOT;
		b.seed = 20;
		b.anchor = new Vec3(0, 0, 0);
		b.sway = 0;
		if (!wide) {
			root([new Vec3(-3.3, -0.6, 1.6), new Vec3(-2.75, 1.0, 1.2), new Vec3(-3.05, 3.2, 0.9), new Vec3(-2.9, 5.6, 0.6), new Vec3(-2.5, 8.2, 0.2), new Vec3(-3.0, 11.5, -0.2), new Vec3(-2.6, 15, -0.6)], 0.36, 3);
			root([new Vec3(-3.0, 0.5, 1.4), new Vec3(-2.2, 0.35, 1.7), new Vec3(-1.5, -0.1, 2.1), new Vec3(-1.0, -0.6, 2.3)], 0.17, 2);
			root([new Vec3(-2.9, 7.6, 0.3), new Vec3(-2.0, 8.6, 0.0), new Vec3(-1.3, 8.9, -0.2)], 0.12, 2);
			root([new Vec3(3.4, -0.6, 1.5), new Vec3(2.75, 0.5, 1.9), new Vec3(1.9, 0.1, 2.3), new Vec3(1.3, -0.6, 2.5)], 0.2, 3);
			root([new Vec3(3.3, 5.2, 0.9), new Vec3(2.85, 7.4, 0.6), new Vec3(3.1, 10, 0.2), new Vec3(2.7, 14, -0.4)], 0.26, 3);
			return {first: first, count: mesh.count - first};
		}
		root([new Vec3(-5.0, -0.8, 1.4), new Vec3(-4.3, 1.0, 1.0), new Vec3(-4.75, 2.9, 0.6), new Vec3(-4.4, 4.8, 0.3), new Vec3(-5.0, 7.5, -0.2)], 0.42, 3);
		root([new Vec3(-4.5, 0.5, 1.2), new Vec3(-3.5, 0.4, 1.5), new Vec3(-2.7, -0.1, 1.9), new Vec3(-2.0, -0.7, 2.1)], 0.2, 2);
		root([new Vec3(-4.6, 4.4, 0.4), new Vec3(-3.6, 5.5, 0.2), new Vec3(-3.0, 6.6, 0.0)], 0.13, 2);
		root([new Vec3(6.0, -0.8, 1.2), new Vec3(5.2, 1.3, 0.9), new Vec3(5.65, 3.2, 0.5), new Vec3(5.3, 5.0, 0.2), new Vec3(5.8, 7.5, -0.2)], 0.4, 3);
		root([new Vec3(5.5, 0.6, 1.2), new Vec3(4.5, 0.5, 1.5), new Vec3(3.7, 0.0, 1.9), new Vec3(3.0, -0.7, 2.1)], 0.2, 2);
		return {first: first, count: mesh.count - first};
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
		arch = gate(13.5, -8.8, -6.8, SPRING, RADIUS, 26, 30);
		b.field(arch, -14, -0.6, -9.9, 14, 26.4, -5.9, 0.16);
		// (the wall goes on to either side, beyond what most windows show)
		for (x in [-60.0, 13.4])
			b.quad(new Vec3(x, -1, -7.0), new Vec3(x + 46.6, -1, -7.0), new Vec3(x + 46.6, 26, -7.0), new Vec3(x, 26, -7.0), new Vec3(0, 0, 1), 1, 0, 1, 0);
		// (glowing veins over its face, hugging it: branching from where it springs)
		b.kind = PaintShader.VEIN;
		for (start in [
			new Vec3(-8.2, 9.4, 0), new Vec3(-5.6, 14.0, 0), new Vec3(6.8, 12.8, 0), new Vec3(1.5, 15.2, 0), new Vec3(-9.4, 5.2, 0), new Vec3(9.2, 7.4, 0),
			new Vec3(-2.4, 16.2, 0), new Vec3(3.6, 17.5, 0), new Vec3(-4.6, 18.5, 0), new Vec3(0.5, 20, 0), new Vec3(8.5, 16.5, 0), new Vec3(-10.5, 13, 0),
			new Vec3(2.2, 22.5, 0), new Vec3(-2.6, 21.5, 0), new Vec3(4.4, 14.6, 0), new Vec3(-11.5, 8, 0), new Vec3(11.6, 11, 0), new Vec3(11.2, 4.5, 0)
		])
			vein(start, rand() * Math.PI * 2, 3.0, 0.07, 3);
		// (moss hanging under the arch: thick strands, in clumps)
		b.kind = PaintShader.STRAND;
		for (k in 0...26) {
			var th = range(0.25, Math.PI - 0.25), z = range(-8.4, -7.0);
			if (k % 3 != 0) th = Math.round(th * 4) / 4 + range(-0.08, 0.08);
			// (from the intrados: march up from inside the opening to the stone)
			var x = Math.cos(th) * (RADIUS - 0.6), yy = SPRING + Math.sin(th) * (RADIUS - 0.6);
			while (yy < 16 && arch(x, yy, z) > 0) {
				x += Math.cos(th) * 0.03;
				yy += Math.sin(th) * 0.03;
			}
			strand(new Vec3(x, yy + 0.02, z), range(0.5, 2.4) * (0.4 + Math.sin(th)));
		}
		// (long vines hanging from the crown, dark against the mist)
		b.kind = PaintShader.ROOT;
		for (v in [[-4.4, 6.0], [-1.6, 3.4], [4.9, 5.2], [6.1, 7.4], [-6.2, 4.2], [2.2, 2.2]]) {
			var x = v[0], z = range(-8.4, -7.2), y = SPRING + Math.sqrt(Math.max(RADIUS * RADIUS - x * x, 0));
			while (y < 16 && arch(x, y, z) > 0)
				y += 0.03;
			var top = new Vec3(x, y, z), len = v[1];
			b.anchor = top;
			b.sway = 0.03;
			b.seed = rand();
			b.tube([top, new Vec3(x + range(-0.3, 0.3), y - len * 0.4, z), new Vec3(x + range(-0.4, 0.4), y - len * 0.75, z + 0.2), new Vec3(x + range(-0.3, 0.3), y - len, z)], 0.07, 0.025, 8, 5, 0.4);
			b.sway = 0;
		}
		lantern(new Vec3(-2.9, 13.3, -7.6), 3.6, 0.1, 0.44);
		lantern(new Vec3(0.4, 14.1, -8.0), 2.4, 0.4, 0.34);
		lantern(new Vec3(3.3, 13.2, -7.4), 5.0, 0.7, 0.48);
		lantern(new Vec3(-5.4, 11.6, -8.2), 2.6, 0.9, 0.3);
		for (p in [
			new Vec3(-7.4, 11.4, -6.0), new Vec3(6, 14, -6.0), new Vec3(0.6, 16.4, -6.0), new Vec3(-9, 6, -6.0), new Vec3(9, 8, -6.0), new Vec3(-3, 18.5, -6.0),
			new Vec3(5, 19.5, -6.0), new Vec3(-7, 20, -6)
		])
			lights.push({pos: p, radius: 5.5, color: PaintShader.acid(), power: 1.3});
	}

	function vein(p:Vec3, a:Float, len:Float, r:Float, depth:Int) {
		var points = [p];
		var at = p;
		for (k in 0...4) {
			a += range(-0.6, 0.6);
			at = new Vec3(at.x + Math.cos(a) * len / 4, at.y + Math.sin(a) * len / 4, 0);
			points.push(at);
		}
		var hugged = [for (q in points) new Vec3(q.x, q.y, face(arch, q.x, q.y, -5.6, -8.8) + 0.02)];
		// (only where there is stone to grow on)
		for (q in hugged)
			if (q.z < -7.4) return;
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
		b.tube([top, new Vec3(top.x + bend, top.y - len * 0.5, top.z), new Vec3(top.x + bend * 2.5, top.y - len, top.z + bend)], range(0.025, 0.05), 0.008, 5, 4);
		b.sway = 0;
	}

	function lantern(hook:Vec3, drop:Float, seed:Float, size:Float) {
		var b = mesh;
		var c = new Vec3(hook.x, hook.y - drop, hook.z);
		var anchor = new Vec4(hook.x, hook.y, hook.z, 0.07);
		b.anchor = hook;
		b.sway = anchor.w;
		b.seed = seed;
		cage(hook, c, size, 1.1);
		b.sway = 0;
		lights.push({pos: c, radius: 5, color: PaintShader.magenta(), power: 3.4, anchor: anchor, seed: seed});
	}

	// a lantern's cage about c, hung from hook: a long drop of lattice,
	// pointed at both ends, a knot over it and a tassel under it
	function cage(hook:Vec3, c:Vec3, size:Float, tassel:Float) {
		var b = mesh;
		b.kind = PaintShader.ROOT;
		b.tube([hook, new Vec3(c.x, c.y + size * 1.7, c.z)], 0.02, 0.02, 2, 5);
		b.tube([new Vec3(c.x, c.y + size * 1.95, c.z), new Vec3(c.x, c.y + size * 1.55, c.z)], size * 0.09, size * 0.16, 2, 8);
		b.tube([new Vec3(c.x, c.y - size * 1.7, c.z), new Vec3(c.x + 0.02, c.y - size * (1.7 + tassel), c.z)], size * 0.07, 0.006, 3, 5);
		b.kind = PaintShader.CAGE;
		var profile:Array<Float> = [];
		for (k in 0...15) {
			var t = k / 14, a = t * Math.PI;
			// (fullest a little below its middle)
			profile.push(size * Math.pow(Math.sin(a), 0.8) * (0.78 + 0.3 * t * (1 - t) * 4 * (t - 0.2)));
			profile.push(size * 1.7 * Math.cos(a));
		}
		b.lathe(c, profile, 22, true);
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

	function sprouts(f:Field, c:Vec3, spread:Float, count:Int, size = 1.0):Glow {
		var b = mesh;
		for (k in 0...count) {
			var x = c.x + range(-spread, spread), z = c.z + range(-spread, spread) * 0.6;
			var y = ground(f, x, z, c.y + 0.6);
			if (y < c.y - 0.6) continue;
			var base = new Vec3(x, y - 0.02, z);
			var h = range(0.1, 0.3) * size, tip = new Vec3(base.x + range(-0.05, 0.05) * size, base.y + h, base.z);
			b.seed = rand();
			b.extra = 0;
			b.kind = PaintShader.STEM;
			b.tube([base, tip], 0.009 * size, 0.006 * size, 2, 4);
			b.kind = PaintShader.BULB;
			var r = range(0.02, 0.038) * size;
			b.lathe(tip, [0.0, r * 1.3, r * 0.8, r * 0.5, r, -r * 0.3, 0.0, -r], 8);
		}
		return {pos: new Vec3(c.x, c.y + 0.25, c.z), radius: 1.3, color: PaintShader.magenta(), power: 0.5};
	}

	function growth() {
		// (cyan on the bridge to the right, acid on the cliff's ledges)
		caps(bridge, 4.6, -11.2, 5.0, 1.5, 9, 0.2, false);
		lights.push({pos: new Vec3(4.6, 5.5, -10.8), radius: 3.6, color: PaintShader.cyan(), power: 1.6});
		caps(cliff, -6.4, -10.6, 3.4, 1.3, 7, 0.22, true);
		lights.push({pos: new Vec3(-6.4, 3.9, -10.0), radius: 3.5, color: PaintShader.acid(), power: 1.2});
		caps(cliff, -7.2, -12.0, 6.9, 1.2, 6, 0.24, false);
		lights.push({pos: new Vec3(-7.2, 7.4, -11.4), radius: 3.5, color: PaintShader.cyan(), power: 1.3});
		// (magenta sprouts)
		lights.push(sprouts(bridge, new Vec3(7.2, 5.0, -11.0), 0.7, 10, 2.2));
		lights.push(sprouts(cliff, new Vec3(-4.6, 3.4, -10.4), 0.6, 8, 2.2));
		lights.push(sprouts(cliff, new Vec3(-8.6, 10.2, -13.0), 0.8, 9, 2.6));
		// (on the rubble by the bridge's foot, over the water)
		caps(bridge, 2.6, -9.9, 0.3, 0.5, 5, 0.14, false);
		lights.push({pos: new Vec3(2.6, 0.6, -9.8), radius: 2.4, color: PaintShader.cyan(), power: 1.2});
	}

	function water() {
		var b = mesh;
		b.kind = PaintShader.PAD;
		for (k in 0...70) {
			var near = k < 24;
			var x = near ? range(-3.6, 3.8) : range(-7, 8), z = near ? range(-1.4, 1.2) : range(-16, -1.0);
			b.extra = rand() < 0.35 ? 1 : 0;
			b.seed = rand();
			b.pad(new Vec3(x, 0.012, z), range(0.12, 0.38), range(0, 6.28), 16);
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
}
