import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The gallery's effects: each a shader definition (shader({vertex,
// fragment}), compiled when the program is built into the target's
// shading language) drawn over a whole box (FxBox), its knobs a uniform
// block: four values from 0 to 1 and two colours. They share the triangle
// over the box and the noise below; each fragment stage is the effect.
@:structInit @:publicFields class FxVertex {
	var pos:Vec2; // clip space
}

@:structInit @:publicFields class FxVaryings {
	var clip:Vec4;
	var uv:Vec2; // 0, 0 the box's top left
}

@:structInit @:publicFields class FxParams {
	var frame:Vec4; // x, y: the box in pixels, z: seconds, w: unused
	var knobs:Vec4; // the effect's four knobs, each 0 to 1
	var a:Vec4; // rgb: the first colour
	var b:Vec4; // rgb: the second colour
}

function fxVertex(v:FxVertex):FxVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

// --- noise (value noise, its octaves summed)

function hash21(p:Vec2):Float
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);

function noise(p:Vec2):Float {
	var i = floor(p), f = fract(p);
	var u = f * f * (vec2(3, 3) - f * 2);
	var a = hash21(i), b = hash21(i + vec2(1, 0)), c = hash21(i + vec2(0, 1)), d = hash21(i + vec2(1, 1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

function fbm(p:Vec2):Float {
	var v = 0.0, a = 0.5, q = p, k = 0.0;
	while (k < 5) {
		v += a * noise(q);
		q = q * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
		k += 1;
	}
	return v;
}

// (the box's point from its centre, its short side 1 across)
function centred(uv:Vec2, f:Vec4):Vec2 {
	var s = min(f.x, f.y);
	return (uv - vec2(0.5, 0.5)) * vec2(f.x / s, f.y / s);
}

// --- liquid metal: a domain-warped field folded into chrome's bands
final MetalShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs;
		var uv = centred(i.uv, p.fx.frame) * (1.4 + k.y * 3);
		var t = p.fx.frame.z * (0.08 + k.x * 0.5);
		var q = vec2(fbm(uv + vec2(0, t)), fbm(uv + vec2(5.2, 1.3) - vec2(t * 0.7, t * 0.4)));
		var r = fbm(uv + q * (1 + k.z * 4) + vec2(t * 0.5, -t * 0.3));
		var bands = 0.5 + 0.5 * sin(r * 20 + q.x * 6);
		var steel = mix(vec3(0.04, 0.045, 0.06), vec3(0.93, 0.95, 1.0), smoothstep(0.1, 0.9, bands));
		var tint = p.fx.a.xyz * pow(1 - bands, 4) * 0.25 + p.fx.b.xyz * pow(bands, 24) * (0.6 + k.w);
		var edge = smoothstep(0.75, 0.0, length(centred(i.uv, p.fx.frame)));
		return vec4((steel + tint) * (0.55 + 0.45 * edge), 1);
	}
});

// (frost's background: soft lights drifting over a dark gradient)
function lights(uv:Vec2, t:Float, a:Vec3, b:Vec3):Vec3 {
	var c = mix(vec3(0.03, 0.035, 0.06), vec3(0.08, 0.06, 0.14), uv.y);
	var k = 0.0;
	while (k < 6) {
		var at = vec2(0.5 + 0.38 * sin(t * 0.31 + k * 1.7), 0.5 + 0.34 * cos(t * 0.23 + k * 2.3));
		var d = length(uv - at);
		var col = mix(a, b, 0.5 + 0.5 * sin(k * 1.3));
		c += col * smoothstep(0.22, 0.0, d) * 0.9;
		k += 1;
	}
	return c;
}

// --- glass and frost: a pane over drifting lights, the lights behind it
// bent by its noise, spread (five taps) and tinted, its edge catching light
final FrostShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, f = p.fx.frame, t = f.z;
		var aspect = f.x / f.y;
		var uv = i.uv;
		var pane = (i.uv - vec2(0.5, 0.5)) * vec2(aspect, 1);
		var half = vec2(aspect * 0.3, 0.3);
		var dq = abs(pane) - half + vec2(0.06, 0.06);
		var sd = length(max(dq, vec2(0, 0))) + min(max(dq.x, dq.y), 0) - 0.06;
		var sharp = lights(uv, t, p.fx.a.xyz, p.fx.b.xyz);
		var bend = (vec2(noise(uv * 18), noise(uv * 18 + vec2(7, 3))) - vec2(0.5, 0.5)) * (0.01 + k.y * 0.06);
		var spread = 0.004 + k.x * 0.05;
		var g = lights(uv + bend, t, p.fx.a.xyz, p.fx.b.xyz) * 0.2;
		g += lights(uv + bend + vec2(spread, 0), t, p.fx.a.xyz, p.fx.b.xyz) * 0.2;
		g += lights(uv + bend - vec2(spread, 0), t, p.fx.a.xyz, p.fx.b.xyz) * 0.2;
		g += lights(uv + bend + vec2(0, spread), t, p.fx.a.xyz, p.fx.b.xyz) * 0.2;
		g += lights(uv + bend - vec2(0, spread), t, p.fx.a.xyz, p.fx.b.xyz) * 0.2;
		var frost = g * (0.85 + 0.25 * k.z) + vec3(0.06, 0.07, 0.09) * k.z + vec3(noise(uv * 260) * 0.035);
		var inside = smoothstep(0.003, -0.003, sd);
		var rim = smoothstep(0.012, 0.0, abs(sd)) * (0.35 + 0.65 * smoothstep(-0.3, 0.3, -pane.y - pane.x * 0.3));
		var c = mix(sharp, frost, inside) + vec3(rim * (0.5 + k.w * 0.5));
		return vec4(c, 1);
	}
});

// --- glow: a ring of light, its falloff one over the distance, two
// colours around it, sparks circling
final GlowShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, t = p.fx.frame.z;
		var uv = centred(i.uv, p.fx.frame);
		var r = 0.18 + k.x * 0.18 + 0.01 * sin(t * 2);
		var d = abs(length(uv) - r);
		var side = 0.5 + 0.5 * sin(uv.x * 4 + uv.y * 3 + t * (0.4 + k.z * 2));
		var col = mix(p.fx.a.xyz, p.fx.b.xyz, side);
		var glow = (0.004 + k.y * 0.01) / (d + 0.002);
		var c = col * glow + vec3(1, 1, 1) * smoothstep(0.006, 0.0, d) * 0.6;
		var s = 0.0;
		while (s < 3) {
			var a = t * (0.8 + s * 0.35) + s * 2.1;
			var at = vec2(cos(a), sin(a)) * r;
			c += mix(p.fx.b.xyz, vec3(1, 1, 1), 0.5) * (0.0012 / (length(uv - at) + 0.003)) * (0.5 + k.w);
			s += 1;
		}
		var bg = vec3(0.02, 0.022, 0.035) + col * 0.05 * smoothstep(0.9, 0.0, length(uv));
		return vec4(bg + c * c * 0.9 + c * 0.25, 1);
	}
});

// --- fire: noise rising through a flame's shape, its heat mapped from
// black through red and orange to white
final FireShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, t = p.fx.frame.z, f = p.fx.frame;
		var aspect = f.x / f.y;
		var x = (i.uv.x - 0.5) * aspect, y = 1 - i.uv.y;
		var speed = 0.6 + k.x * 2.2;
		var n = fbm(vec2(x * (3 + k.y * 4), y * 2.4 - t * speed));
		var n2 = fbm(vec2(x * 7 + 3, y * 5 - t * speed * 1.7));
		var height = 0.45 + k.z * 0.5;
		var shape = (1 - y / height) - abs(x) * (1.6 - k.y * 0.6) * (1 + y);
		var heat = clamp(shape + (n - 0.5) * 1.1 + (n2 - 0.5) * 0.35, 0, 1.2);
		var c = vec3(1.5 * heat, 1.5 * heat * heat * heat, pow(heat, 6) * 1.2);
		c = c * mix(vec3(1, 1, 1), p.fx.a.xyz * 1.6, k.w);
		var smoke = smoothstep(0.0, 0.7, y) * fbm(vec2(x * 2, y * 2 - t * 0.4)) * 0.08;
		return vec4(c + vec3(smoke, smoke, smoke * 1.2) + vec3(0.02, 0.015, 0.02), 1);
	}
});

// --- mesh gradient: four colours at points that drift, mixed by their
// inverse distances, the plane gently warped
final MeshShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, t = p.fx.frame.z * (0.15 + k.x * 0.8);
		var uv = i.uv + (vec2(noise(i.uv * 3 + vec2(t, 0)), noise(i.uv * 3 + vec2(0, t) + vec2(4, 4))) - vec2(0.5, 0.5)) * (0.05 + k.z * 0.3);
		var p0 = vec2(0.2 + 0.15 * sin(t * 1.1), 0.25 + 0.15 * cos(t * 0.9));
		var p1 = vec2(0.8 + 0.12 * cos(t * 0.8), 0.2 + 0.18 * sin(t * 1.3));
		var p2 = vec2(0.75 + 0.15 * sin(t * 0.7 + 2), 0.8 + 0.12 * cos(t * 1.2));
		var p3 = vec2(0.25 + 0.12 * cos(t * 1.4 + 1), 0.78 + 0.14 * sin(t * 0.6));
		var e = 1.5 + k.y * 3;
		var w0 = 1 / pow(length(uv - p0) + 0.02, e), w1 = 1 / pow(length(uv - p1) + 0.02, e);
		var w2 = 1 / pow(length(uv - p2) + 0.02, e), w3 = 1 / pow(length(uv - p3) + 0.02, e);
		var c0 = p.fx.a.xyz, c1 = p.fx.b.xyz, c2 = vec3(1, 0.75, 0.45), c3 = vec3(0.12, 0.1, 0.3);
		var c = (c0 * w0 + c1 * w1 + c2 * w2 + c3 * w3) / (w0 + w1 + w2 + w3);
		return vec4(c + vec3((hash21(i.uv * f2(p.fx.frame)) - 0.5) * 0.02 * k.w), 1);
	}
});

function f2(f:Vec4):Vec2
	return vec2(f.x, f.y);

// --- grain: a soft gradient and its sun, under film grain that changes
// each frame, its size and amount the knobs
final GrainShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, f = p.fx.frame, t = f.z;
		var g = clamp(i.uv.y * 0.9 + 0.1 * sin(i.uv.x * 3 + t * 0.3), 0, 1);
		var c = mix(p.fx.a.xyz, p.fx.b.xyz, g);
		var sun = centred(i.uv, f) - vec2(0.18 * sin(t * 0.2), -0.05 + 0.04 * cos(t * 0.3));
		c += vec3(1, 0.85, 0.6) * smoothstep(0.28 + k.z * 0.2, 0.0, length(sun)) * 0.55;
		var cell = floor(i.uv * f2(f) / (1 + k.y * 3));
		var n = hash21(cell + vec2(floor(t * 24) * 17.3, floor(t * 24) * 3.1)) - 0.5;
		var amount = 0.04 + k.x * 0.3;
		var lum = dot(c, vec3(0.3, 0.6, 0.1));
		return vec4(c + vec3(n * amount * (0.4 + lum)), 1);
	}
});

// (Bayer's ordered thresholds, 8 by 8, from 2 by 2 nested)
function bayer2(a:Vec2):Float {
	var b = floor(a);
	return fract(b.x / 2 + b.y * b.y * 0.75);
}

function bayer8(a:Vec2):Float
	return bayer2(a * 0.25) * 0.0625 + bayer2(a * 0.5) * 0.25 + bayer2(a);

// --- dither: a lit sphere and a wave behind it in a handful of levels
// of two colours, ordered (Bayer) at a pixel size
final DitherShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, f = p.fx.frame, t = f.z;
		var px = 1 + floor(k.x * 6);
		var cell = floor(i.uv * f2(f) / px);
		var uv = centred((cell * px + vec2(px * 0.5, px * 0.5)) / f2(f), f);
		var l = normalize(vec3(cos(t * 0.6), 0.6, sin(t * 0.6) + 0.8));
		var d = length(uv);
		var shade = 0.35 + 0.25 * sin(uv.x * 6 + t) * sin(uv.y * 5 - t * 0.7);
		if (d < 0.32) {
			var z = sqrt(0.32 * 0.32 - d * d) / 0.32;
			var n = vec3(uv.x / 0.32, -uv.y / 0.32, z);
			shade = clamp(dot(n, l), 0, 1) * 0.95 + 0.05;
		}
		var levels = 2 + floor(k.y * 4);
		var q = floor(shade * (levels - 1) + bayer8(cell)) / (levels - 1);
		return vec4(mix(p.fx.a.xyz, p.fx.b.xyz, clamp(q, 0, 1)), 1);
	}
});

// --- electric: arcs between two points, each a line displaced by noise
// that changes many times a second, a white core in a coloured glow
final ElectricShader = shader({
	vertex: function(v:FxVertex):FxVaryings return fxVertex(v),
	fragment: function(i:FxVaryings, p:{fx:FxParams}):Vec4 {
		var k = p.fx.knobs, f = p.fx.frame, t = f.z;
		var uv = centred(i.uv, f);
		var span = f.x / min(f.x, f.y) * 0.4;
		var c = vec3(0.015, 0.018, 0.03);
		var flick = floor(t * (8 + k.x * 22));
		var s = 0.0;
		while (s < 3) {
			var x = uv.x;
			var env = smoothstep(span, span * 0.6, abs(x));
			var off = (fbm(vec2(x * (3 + k.y * 6) + s * 7.3, flick * 0.37 + s)) - 0.5) * (0.25 + k.z * 0.5) * env;
			var d = abs(uv.y - off);
			var w = s == 0 ? 1.0 : 0.45;
			c += p.fx.a.xyz * (0.0025 / (d + 0.0015)) * w;
			c += vec3(1, 1, 1) * smoothstep(0.004, 0.0, d) * w * 0.8;
			s += 1;
		}
		var ends = 0.012 / (length(uv - vec2(-span, 0)) + 0.01) + 0.012 / (length(uv - vec2(span, 0)) + 0.01);
		c += p.fx.b.xyz * ends * (0.6 + k.w);
		return vec4(c * (0.85 + 0.15 * hash21(vec2(flick, 1))), 1);
	}
});
