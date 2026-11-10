import Sdf;

// The ruins' stone as signed distance fields (Sdf), meshed by
// Builder.field: worn walls and arcades whose top courses have fallen,
// some bays broken through, edges rounded and eroded, footings sunk in
// rubble; and the cliff of ledges the moth lives on.
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

function arcade(a:Arcade):Field {
	var x0 = a.x0, x1 = a.x1, y0 = a.y0, r = a.r, pier = a.pier, top = a.top, spring = a.spring, seed = a.seed;
	var bay = 2 * r + pier;
	var count = Std.int(Math.max(1, Math.floor((x1 - x0 - pier) / bay)));
	var start = x0 + (x1 - x0 - count * bay - pier) / 2;
	var cx = (x0 + x1) / 2, hx = (x1 - x0) / 2, cz = (a.z0 + a.z1) / 2, hz = (a.z1 - a.z0) / 2;
	var course = Math.min(0.55, Math.max(0.28, r * 0.16)), col = course * 1.7;
	var deck = course * 1.3;
	var cy = (y0 + top) / 2, hy = (top - y0) / 2;
	var broken = a.broken == null ? 0.0 : a.broken, wear = a.wear == null ? 1.0 : a.wear;
	var amp = course * 0.45 * wear, freq = 0.5 / course;
	var ring = a.ring == true, ends = a.ends == null ? bay * 0.8 : a.ends;
	return (x, y, z) -> {
		var lx = x - cx, lz = z - cz;
		var d = box(lx, y - cy, lz, hx, hy, hz, course * 0.35);
		d = Math.min(d, box(lx, y - top - deck * 0.5, lz, hx + course * 0.3, deck * 0.5, hz + course * 0.45, course * 0.3));
		// (the nearest opening, and its archivolt)
		var k = Math.round((x - start - pier - r) / bay);
		k = k < 0 ? 0 : (k > count - 1 ? count - 1 : k);
		var ox = start + pier + r + k * bay;
		var ex = x - ox;
		if (ring) {
			var dy = Math.max(y - spring, 0);
			var arc = Math.abs(Math.sqrt(ex * ex + dy * dy) - r - course * 0.6) - course * 0.6;
			d = Math.min(d, Math.max(arc, Math.abs(lz) - hz - course * 0.3));
		}
		d = smax(d, -opening(ex, y, r, spring), course * 0.5);
		// (bays broken through from above: a notch widening upwards)
		if (hash1(k, seed + 3) < broken) {
			var floor = spring + r * (0.3 + 0.8 * hash1(k, seed + 5));
			var off = (hash1(k, seed + 7) - 0.5) * r;
			var w = r * 0.2 + (y - floor) * 0.6 + (noise1(y * 2.3, seed + k) - 0.5) * course * 2;
			d = Math.max(d, -Math.max(Math.abs(ex - off) - w, floor - y));
		}
		// (the skyline: courses fallen, more towards the ends)
		var end = Math.max(0, Math.abs(lx) - hx + ends) * 0.9;
		var sky = top + deck - (lost(x, col, seed) + Math.floor(end / course)) * course;
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

// a worn block of masonry between two corners: its top courses fallen
// here and there, its edges eroded, a cushion of moss over its top's
// edge; calm (x, y, z, radius, for each spot) keeps a face flat where something is carved,
// fallen how much of its top has come down
function slab(x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float, seed:Float, wear = 1.0, ?calm:Array<Float>, fallen = 1.0):Field {
	var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, cz = (z0 + z1) / 2, hx = (x1 - x0) / 2, hy = (y1 - y0) / 2, hz = (z1 - z0) / 2;
	var course = 0.28, col = 0.5;
	var amp = 0.13 * wear;
	return (x, y, z) -> {
		var still = 1.0;
		if (calm != null) {
			var k = 0;
			while (k < calm.length) {
				var gx = x - calm[k], gy = y - calm[k + 1], gz = z - calm[k + 2];
				still = Math.min(still, 0.12 + 0.88 * smooth(calm[k + 3], calm[k + 3] * 2.5, Math.sqrt(gx * gx + gy * gy + gz * gz)));
				k += 4;
			}
		}
		// (its outline seen from above ragged: faces wander in and out)
		var ox = (noise1(z * 0.9, seed + 1) - 0.5) * 0.5 * wear * still, oz = (noise1(x * 0.9, seed) - 0.5) * 0.5 * wear * still;
		var d = box(x - cx, y - cy, z - cz, hx + ox, hy, hz + oz, 0.1);
		var sky = y1 - (lost(x + seed * 13, col, seed) * course * 0.6 + lost(z + seed * 7, col * 1.3, seed + 1) * course * 0.3) * fallen;
		d = Math.max(d, y - sky);
		if (d > amp * 2 + 0.25) return d;
		// (stones gone from the front edge of its top: bites out of the lip)
		var c = Math.floor(x / 0.55), r = 0.15 + 0.22 * hash1(c, seed + 9);
		if (hash1(c, seed + 8) < 0.7 * still) {
			var bx = x - (c + 0.5) * 0.55, by = y - sky + 0.02, bz = z - (z1 + oz) - 0.02;
			d = smax(d, r - Math.sqrt(bx * bx + by * by * 1.6 + bz * bz), 0.05);
		}
		var a = amp * still;
		// (eroded harder low, where the water was)
		a *= 1 + 0.8 * smooth(1.2, -0.6, y);
		d += fbm3(x * 1.3 + seed, y * 1.3, z * 1.3) * a * 2 + (noise3(x * 6, y * 6 + seed, z * 6) - 0.5) * a * 0.45;
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
