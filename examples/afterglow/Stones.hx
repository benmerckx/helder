import Sdf;

// The ruins' stone as signed distance fields (Sdf), meshed by
// Builder.field: masonry whose blocks stand in and out of its faces
// (brick: the same blocks PaintShader draws the joints of), top courses
// fallen in steps, ledges corbelled out under their lips, some bays broken
// through, footings sunk in rubble.
inline var ROW = 0.3;

inline function tri(x:Float):Float
	return Math.abs(2 * frac(x) - 1);

// how far the block at (a along, b up) of a face stands out of it (in:
// negative, a block gone: a hole); the blocks are Mood.bricks' (the
// shader's), from sequences that come out the same in a shader's floats
function brick(a:Float, b:Float, s:Float):Float {
	var bb = b + 0.035 * Math.sin(a * 1.3 + s * 5) + 0.02 * Math.sin(a * 3.7 + s * 2);
	// (courses in pairs, the joint between a pair higher or lower; a block
	// now and then as long as two)
	var pair = Math.floor(bb / (2 * ROW)), fy = bb - pair * 2 * ROW;
	var split = ROW + 0.085 * (2 * tri(pair * 0.4656 + s * 0.13) - 1);
	var upper = fy >= split;
	var row = pair * 2 + (upper ? 1 : 0), h = upper ? 2 * ROW - split : split;
	var w = 0.42 + 0.3 * tri(row * 0.381966 + s * 0.37);
	var u = a / w + frac(row * 0.618034 + s * 0.71);
	var col = Math.floor(u), two = Math.floor(u / 2) * 2;
	var long = tri(two * 0.2763932 + row * 0.6457513 + s * 0.23) > 0.72;
	if (long) col = two;
	var fa = (u - col) * w, fb = upper ? fy - split : fy;
	if (long) w *= 2;
	var g = tri(col * 0.7548777 + row * 0.5698403 + s * 0.31), gone = tri(col * 0.4142136 + row * 0.7320508 + s * 0.53);
	var edge = smooth(0, 0.06, Math.min(Math.min(fa, w - fa), Math.min(fb, h - fb)));
	return (gone > 0.95 ? -0.16 : (g - 0.5) * 0.1) * edge - 0.025 * (1 - edge);
}
typedef Arcade = {
	var x0:Float;
	var x1:Float;
	var z0:Float;
	var z1:Float;
	var y0:Float;
	var spring:Float;
	var r:Float;
	var pier:Float;
	var top:Float;
	var seed:Float;
	var ?broken:Float; // the share of bays broken through from above
	var ?wear:Float;
	var ?ring:Bool; // an archivolt standing out about each opening
	var ?ends:Float; // how far in from either end its top falls away
}

// the wall's courses lost from its top at x, in courses: a stepped,
// crumbled skyline, lower towards the broken ends
function lost(x:Float, col:Float, seed:Float):Float {
	var u = x / col, c = Math.floor(u), f = u - c;
	var a = Math.pow(hash1(c, seed), 2.5) * 3, b = Math.pow(hash1(c + 1, seed), 2.5) * 3;
	return Math.floor(a + (b - a) * smooth(0.8, 1, f) + 0.5 * smooth(0.8, 1, f));
}

function arcade(a:Arcade, bs = 0.0):Field {
	var x0 = a.x0, x1 = a.x1, y0 = a.y0, r = a.r, pier = a.pier, top = a.top, spring = a.spring, seed = a.seed;
	var bay = 2 * r + pier;
	var count = Std.int(Math.max(1, Math.floor((x1 - x0 - pier) / bay)));
	var start = x0 + (x1 - x0 - count * bay - pier) / 2;
	var cx = (x0 + x1) / 2, hx = (x1 - x0) / 2, cz = (a.z0 + a.z1) / 2, hz = (a.z1 - a.z0) / 2;
	var course = ROW, col = course * 1.7;
	var deck = course;
	var cy = (y0 + top) / 2, hy = (top - y0) / 2;
	var broken = a.broken == null ? 0.0 : a.broken, wear = a.wear == null ? 1.0 : a.wear;
	var amp = course * 0.22 * wear, freq = 0.5 / course;
	var ring = a.ring == true, ends = a.ends == null ? bay * 0.8 : a.ends;
	return (x, y, z) -> {
		var lx = x - cx, lz = z - cz;
		var d = box(lx, y - cy, lz, hx, hy, hz, 0.04);
		if (d > 1.2) return d;
		var relief = brick(x, y, bs);
		d = box(lx, y - cy, lz, hx, hy, hz + relief, 0.04);
		// (its deck: a course standing out, under the top)
		d = Math.min(d, box(lx, y - top + deck * 0.5, lz, hx + 0.1, deck * 0.5, hz + 0.16 + relief * 0.5, 0.03));
		// (the nearest opening, and its archivolt)
		var k = Math.round((x - start - pier - r) / bay);
		k = k < 0 ? 0 : (k > count - 1 ? count - 1 : k);
		var ox = start + pier + r + k * bay;
		var ex = x - ox;
		if (ring) {
			var dy = Math.max(y - spring, 0);
			var arc = Math.abs(Math.sqrt(ex * ex + dy * dy) - r - course * 0.6) - course * 0.6;
			d = Math.min(d, Math.max(arc, Math.abs(lz) - hz - 0.14));
		}
		d = smax(d, -opening(ex, y, r, spring), 0.06);
		// (bays broken through from above: a notch in steps, widening upwards)
		if (hash1(k, seed + 3) < broken) {
			var floor = spring + r * (0.3 + 0.8 * hash1(k, seed + 5));
			var off = (hash1(k, seed + 7) - 0.5) * r;
			var up = Math.floor((y - floor) / course) * course;
			var w = r * 0.25 + up * 0.55 + (hash1(Math.floor(y / course), seed + k) - 0.5) * course * 1.5;
			d = Math.max(d, -Math.max(Math.abs(ex - off) - w, floor - y));
		}
		// (the skyline: courses fallen, more towards the ends)
		var end = Math.max(0, Math.abs(lx) - hx + ends) * 0.9;
		var sky = top - (lost(x, col, seed) + Math.floor(end / course)) * course;
		d = Math.max(d, y - sky);
		// (wear: only near the surface, where it shows)
		if (d < amp * 1.6 + course) d += fbm3(x * freq, y * freq, z * freq) * amp * 2 + (noise3(x * freq * 4, y * freq * 4, z * freq * 4) - 0.5) * amp * 0.5;
		// (footings sunk in rubble)
		var px = x - (start + k * bay + pier * 0.5), px2 = x - (start + (k + 1) * bay + pier * 0.5);
		var foot = Math.min(Math.abs(px), Math.abs(px2));
		if (y < 1.2) {
			var mound = box(foot, y - (-0.4), lz, pier * 0.5 + course * 1.2, 0.6, hz + course * 1.2, course * 1.5);
			mound += fbm3(x * freq * 1.5, y * freq * 1.5, z * freq * 1.5) * course * 1.8;
			d = smin(d, mound, course * 0.8);
		}
		return d;
	};
}

// the great arch: a wall over everything, one wide opening in it, two
// orders of voussoirs standing out about it, its blocks in relief
function gate(hx:Float, z0:Float, z1:Float, spring:Float, r:Float, top:Float, bs:Float):Field {
	var cz = (z0 + z1) / 2, hz = (z1 - z0) / 2, cy = (top - 1.2) / 2, hy = (top + 1.2) / 2;
	return (x, y, z) -> {
		var lz = z - cz;
		var d = box(x, y - cy, lz, hx, hy, hz + 0.5, 0.04);
		if (d > 1) return d;
		var relief = brick(x, y, bs);
		d = box(x, y - cy, lz, hx, hy, hz + relief, 0.04);
		var dy = Math.max(y - spring, 0), round = Math.sqrt(x * x + dy * dy);
		var hole = y > spring ? round - r : Math.abs(x) - r;
		// (voussoirs: wedges about the opening, each a little in or out)
		var a = Math.atan2(dy, x), wedge = Math.floor(a * r / 0.55);
		var out = 0.2 + 0.07 * tri(wedge * 0.618034 + bs);
		var joint = 0.03 * (1 - smooth(0, 0.07, Math.abs(frac(a * r / 0.55) - 0.5) * 0.55));
		if (y <= spring) {
			out = 0.2 + 0.07 * tri(Math.floor(y / ROW) * 0.618034 + bs);
			joint = 0;
		}
		d = Math.min(d, Math.max(Math.max(hole - 0.75, -hole), Math.abs(lz) - hz - out + joint));
		d = Math.min(d, Math.max(Math.max(hole - 1.5, 0.75 - hole), Math.abs(lz) - hz - out * 0.45));
		d = smax(d, -hole, 0.05);
		// (stones gone from the intrados here and there)
		if (d < 0.4) d += fbm3(x * 0.8, y * 0.8, z * 0.8 + bs) * 0.12;
		return d;
	};
}

// a worn block of masonry between two corners: a lip over its top course,
// the courses under it stepping back (a corbel), its blocks in relief,
// its top courses fallen here and there, a cushion of moss over its top's
// edge; calm (x, y, z, radius, for each spot) keeps a face flat where
// something is carved, fallen how much of its top has come down, under how
// far it steps back below its lip
function slab(x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float, seed:Float, wear = 1.0, ?calm:Array<Float>, fallen = 1.0, bs = 0.0, under = 1.0):Field {
	var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, cz = (z0 + z1) / 2, hx = (x1 - x0) / 2, hy = (y1 - y0) / 2, hz = (z1 - z0) / 2;
	var course = ROW, col = 0.5;
	var amp = 0.06 * wear;
	return (x, y, z) -> {
		var far = box(x - cx, y - cy, z - cz, hx, hy, hz, 0.04);
		if (far > 0.7) return far;
		var still = 1.0;
		if (calm != null) {
			var k = 0;
			while (k < calm.length) {
				var gx = x - calm[k], gy = y - calm[k + 1], gz = z - calm[k + 2];
				still = Math.min(still, 0.08 + 0.92 * smooth(calm[k + 3], calm[k + 3] * 2.2, Math.sqrt(gx * gx + gy * gy + gz * gz)));
				k += 4;
			}
		}
		// (its outline seen from above ragged: faces wander in and out)
		var ox = (noise1(z * 0.9, seed + 1) - 0.5) * 0.3 * wear * still, oz = (noise1(x * 0.9, seed) - 0.5) * 0.3 * wear * still;
		// (under the lip the courses step back, then the body goes down)
		var rows = Math.floor((y1 - y) / course);
		var back = Math.min(Math.min(Math.max(rows, 0), 3) * 0.1, Math.min(hx, hz) * 0.3) * under * still;
		var lip = rows < 1 ? 0.05 : 0;
		var d = box(x - cx, y - cy, z - cz, hx + ox - back + lip + brick(z, y, bs) * still, hy, hz + oz - back + lip + brick(x, y, bs) * still, 0.03);
		var sky = y1 - (lost(x + seed * 13, col, seed) * course + lost(z + seed * 7, col * 1.3, seed + 1) * course * 0.5) * fallen;
		d = Math.max(d, y - sky);
		// (stones gone from the front edge of its top: bites out of the lip)
		var c = Math.floor(x / 0.55), r = 0.15 + 0.22 * hash1(c, seed + 9);
		if (hash1(c, seed + 8) < 0.6 * still * wear) {
			var bx = x - (c + 0.5) * 0.55, by = y - sky + 0.02, bz = z - (z1 + oz) - 0.02;
			d = smax(d, r - Math.sqrt(bx * bx + by * by * 1.6 + bz * bz), 0.05);
		}
		var a = amp * still;
		// (eroded harder low, where the water was)
		a *= 1 + 1.5 * smooth(1.0, -0.6, y);
		d += fbm3(x * 1.3 + seed, y * 1.3, z * 1.3) * a * 2 + (noise3(x * 6, y * 6 + seed, z * 6) - 0.5) * a * 0.4;
		// (moss: a lumpy cushion over the top's edge)
		var near = smooth(-0.3, -0.02, y - sky);
		if (near > 0) d -= near * (0.03 + 0.07 * noise3(x * 4.5, y * 3, z * 4.5 + seed));
		return d;
	};
}

// how much moss covers a point facing n (up: its y): patches on what
// faces up (what hangs below a top is the shader's, PaintShader's drips)
function moss(seed:Float):(x:Float, y:Float, z:Float, nx:Float, ny:Float, nz:Float) -> Float
	return (x, y, z, nx, ny, nz) -> {
		var patch = noise3(x * 1.4, y * 1.4, z * 1.4 + seed);
		return smooth(0.35, 0.8, ny) * smooth(0.3, 0.55, patch + ny * 0.15);
	};

// a ruined tower far off: tapering, a window or two, its top broken off
// on a slant, worn at its own scale
function tower(cx:Float, cz:Float, w:Float, h:Float, seed:Float):Field {
	var slant = (hash1(1, seed) - 0.5) * 1.2, cut = h * (0.75 + 0.25 * hash1(2, seed));
	var win = w * 0.22, sill = h * (0.45 + 0.3 * hash1(3, seed));
	return (x, y, z) -> {
		var lx = x - cx, lz = z - cz;
		var taper = 1 - 0.18 * clamp01(y / h);
		var d = box(lx / taper, y - h / 2, lz / taper, w / 2, h / 2, w / 2, w * 0.08) * taper;
		d = Math.max(d, y - cut - lx * slant - (noise1(lx * 2 / w + lz, seed) - 0.5) * w * 0.8);
		d = Math.max(d, -Math.max(opening(lx, y, win, sill), Math.abs(y - sill) - win * 3));
		// (a cornice, half fallen)
		d = Math.min(d, Math.max(box(lx, y - h * 0.6, lz, w * 0.6, w * 0.1, w * 0.6, w * 0.04), lx * slant * 3 - w * 0.2));
		if (d < w * 0.3) d += fbm3(x * 1.5 / w, y * 1.5 / w, z * 1.5 / w + seed) * w * 0.25;
		return d;
	};
}

// a fallen stone: a worn, flattened lump
function rock(cx:Float, cy:Float, cz:Float, s:Float, yaw:Float, seed:Float):Field {
	var co = Math.cos(yaw), si = Math.sin(yaw);
	return (x, y, z) -> {
		var dx = x - cx, dz = z - cz;
		var lx = dx * co - dz * si, lz = dx * si + dz * co;
		var d = box(lx, y - cy, lz, s * 0.6, s * 0.35, s * 0.45, s * 0.2);
		if (d < s * 0.4) d += fbm3(x * 2.2 / s + seed, y * 2.2 / s, z * 2.2 / s) * s * 0.35;
		return d;
	};
}

function union(fields:Array<Field>, k:Float):Field
	return (x, y, z) -> {
		var d = 1e9;
		for (f in fields) d = smin(d, f(x, y, z), k);
		return d;
	};
