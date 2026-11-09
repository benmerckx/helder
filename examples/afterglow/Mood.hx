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

// the mist's colour looking along d (unit): violet above, a cold teal
// glow low in the distance, where the far ruins dissolve
function mist(d:Vec3):Vec3 {
	var up = clamp(d.y * 1.6 + 0.08, -1, 1);
	var low = vec3(0.012, 0.03, 0.06), high = vec3(0.01, 0.006, 0.026);
	var c = mix(low, high, smoothstep(-0.05, 0.6, up));
	return c * (1 + 0.6 * smoothstep(0.35, -0.05, abs(up - 0.05)));
}

// how much of the mist is between the eye and a point dist away, at height y
function haze(dist:Float, y:Float, density:Float):Float {
	var thick = density * (1 + 0.8 * exp(-max(y, 0) * 0.5));
	return 1 - exp(-max(dist - 4, 0) * thick);
}
