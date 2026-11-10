import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// What the scene's shaders share: hashes and noise without sin (a
// phone's sin loses its digits at large arguments), and the mist.

function hash2(p:Vec2):Float {
	var q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += vec3(dot(q, vec3(q.y, q.z, q.x) + vec3(33.33)));
	return fract((q.x + q.y) * q.z);
}

function noise2(p:Vec2):Float {
	var i = floor(p), f = fract(p);
	var u = f * f * (vec2(3) - f * 2);
	var a = hash2(i), b = hash2(i + vec2(1, 0)), c = hash2(i + vec2(0, 1)), d = hash2(i + vec2(1, 1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

function fbm2(p:Vec2):Float
	return noise2(p) * 0.5 + noise2(p * 2.03 + vec2(1.7, 9.2)) * 0.3 + noise2(p * 4.01 + vec2(8.3, 2.8)) * 0.2;

// the mist's colour looking along d (unit): a cold teal glow low in the
// distance, where the far ruins dissolve, blue above it, violet high up
function mist(d:Vec3):Vec3 {
	var horizon = vec3(0.03, 0.065, 0.11), mid = vec3(0.016, 0.028, 0.07), top = vec3(0.01, 0.007, 0.03);
	var c = mix(horizon, mid, smoothstep(0.0, 0.22, d.y));
	c = mix(c, top, smoothstep(0.2, 0.6, d.y));
	return c * (1 + 0.5 * smoothstep(0.12, 0.0, abs(d.y - 0.02)));
}

// how much of the mist is between the eye and a point dist away, at height y
function haze(dist:Float, y:Float, density:Float):Float {
	var thick = density * (0.55 + 1.5 * exp(-max(y, 0) * 0.35));
	return 1 - exp(-max(dist - 4, 0) * thick);
}

function tri(x:Float):Float
	return abs(2 * fract(x) - 1);

// the blocks of a face at f (along, up), as Stones.brick lays them (the
// mesh's relief): x: how far from the block's edge, y: the block's own
// number (0 to 1), z: over 0.95 a block gone, w: how far up the block (0 to 1)
function bricks(f:Vec2, s:Float):Vec4 {
	var bb = f.y + 0.035 * sin(f.x * 1.3 + s * 5) + 0.02 * sin(f.x * 3.7 + s * 2);
	var row = floor(bb / 0.3);
	var w = 0.42 + 0.3 * tri(row * 0.381966 + s * 0.37);
	var u = f.x / w + fract(row * 0.618034 + s * 0.71);
	var col = floor(u);
	var fa = (u - col) * w, fb = bb - row * 0.3;
	return vec4(min(min(fa, w - fa), min(fb, 0.3 - fb)), tri(col * 0.7548777 + row * 0.5698403 + s * 0.31), tri(col * 0.4142136 + row * 0.7320508 + s * 0.53), fb / 0.3);
}
