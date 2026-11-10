// Signed distances on the CPU, for Builder.field: plain floats, nothing
// allocated per sample (the ruins are meshed once, at start). Negative
// inside.
typedef Field = (x:Float, y:Float, z:Float) -> Float;

inline function frac(x:Float):Float
	return x - Math.floor(x);

inline function clamp01(x:Float):Float
	return x < 0 ? 0 : (x > 1 ? 1 : x);

inline function smooth(a:Float, b:Float, x:Float):Float {
	var t = clamp01((x - a) / (b - a));
	return t * t * (3 - 2 * t);
}

// (a hash without sin, as the shaders': doubles keep its digits)
function hash3(x:Float, y:Float, z:Float):Float {
	var a = frac(x * 0.1031), b = frac(y * 0.1030), c = frac(z * 0.0973);
	var d = a * (c + 33.33) + b * (a + 33.33) + c * (b + 33.33);
	a += d;
	b += d;
	c += d;
	return frac((a + b) * c);
}

inline function hash1(x:Float, seed:Float):Float
	return hash3(x, seed, 7.31);

function noise3(x:Float, y:Float, z:Float):Float {
	var i = Math.floor(x), j = Math.floor(y), k = Math.floor(z);
	var u = x - i, v = y - j, w = z - k;
	u = u * u * (3 - 2 * u);
	v = v * v * (3 - 2 * v);
	w = w * w * (3 - 2 * w);
	var a = hash3(i, j, k), b = hash3(i + 1, j, k), c = hash3(i, j + 1, k), d = hash3(i + 1, j + 1, k);
	var e = hash3(i, j, k + 1), f = hash3(i + 1, j, k + 1), g = hash3(i, j + 1, k + 1), h = hash3(i + 1, j + 1, k + 1);
	var ab = a + (b - a) * u, cd = c + (d - c) * u, ef = e + (f - e) * u, gh = g + (h - g) * u;
	var lo = ab + (cd - ab) * v, hi = ef + (gh - ef) * v;
	return lo + (hi - lo) * w;
}

// about -0.5 to 0.5
function fbm3(x:Float, y:Float, z:Float):Float
	return noise3(x, y, z) * 0.5 + noise3(x * 2.03 + 1.7, y * 2.03 + 9.2, z * 2.03 + 3.1) * 0.3
		+ noise3(x * 4.01 + 8.3, y * 4.01 + 2.8, z * 4.01 + 5.5) * 0.2 - 0.5;

function noise1(x:Float, seed:Float):Float {
	var i = Math.floor(x), u = x - i;
	u = u * u * (3 - 2 * u);
	var a = hash1(i, seed);
	return a + (hash1(i + 1, seed) - a) * u;
}

// a box about the origin (half sizes), its edges rounded by r
function box(x:Float, y:Float, z:Float, hx:Float, hy:Float, hz:Float, r:Float):Float {
	var qx = Math.abs(x) - hx + r, qy = Math.abs(y) - hy + r, qz = Math.abs(z) - hz + r;
	var ox = Math.max(qx, 0), oy = Math.max(qy, 0), oz = Math.max(qz, 0);
	return Math.sqrt(ox * ox + oy * oy + oz * oz) + Math.min(Math.max(qx, Math.max(qy, qz)), 0) - r;
}

inline function sphere(x:Float, y:Float, z:Float, r:Float):Float
	return Math.sqrt(x * x + y * y + z * z) - r;

// an arched opening seen face on (through z): a round head at spring, straight sides below
function opening(x:Float, y:Float, r:Float, spring:Float):Float {
	var dy = y - spring;
	var round = Math.sqrt(x * x + dy * dy) - r;
	return dy > 0 ? round : Math.abs(x) - r;
}

function smin(a:Float, b:Float, k:Float):Float {
	var h = clamp01(0.5 + 0.5 * (b - a) / k);
	return b + (a - b) * h - k * h * (1 - h);
}

inline function smax(a:Float, b:Float, k:Float):Float
	return -smin(-a, -b, k);

// a vertical capsule from y0 to y1 at (cx, cz), its radius going from r0 to r1
function pillar(x:Float, y:Float, z:Float, y0:Float, y1:Float, r0:Float, r1:Float):Float {
	var t = clamp01((y - y0) / (y1 - y0));
	var dy = y - (y0 + (y1 - y0) * t);
	return Math.sqrt(x * x + dy * dy + z * z) - (r0 + (r1 - r0) * t);
}
