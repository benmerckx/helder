import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Every builtin of ShaderMath, the math types' operators and the
// statements, once each, so that each back end's compiler sees all the
// emitter writes (GfxTest, WebTest; ShaderTest: the source against
// test/shader/ and the CPU's result).
@:structInit @:publicFields class BuiltinVertex {
	var pos:Vec4;
}

@:structInit @:publicFields class BuiltinVaryings {
	@:position var pos:Vec4;
	var a:Float;
	var b:Vec2;
}

class BuiltinShader implements Shaders {
	@:vertex static function vs(v:BuiltinVertex):BuiltinVaryings {
		var m = mat4(vec4(1, 0, 0, 0), vec4(0, 1, 0, 0), vec4(0, 0, 1, 0), vec4(v.pos.xyz, 1)) * mat4(0.5);
		return {pos: m * v.pos + m.c3 * 0, a: v.pos.w, b: v.pos.xy};
	}

	@:fragment static function fs(i:BuiltinVaryings):Vec4 {
		var x = i.a, v2 = i.b, v3 = vec3(v2, x), v4 = vec4(v3, 1);
		var s = abs(x) + sign(x) + floor(x) + ceil(x) + fract(x) + sqrt(x) + inversesqrt(x + 1) + sin(x) + cos(x) + tan(x) + exp(x) + log(x + 1);
		s += min(x, 1) + max(x, 0) + pow(x, 2) + step(0.5, x) + mix(0, 1, x) + clamp(x, 0, 1) + smoothstep(0, 1, x);
		s += Math.sqrt(x) + Math.abs(-x) + Math.min(x, 2) + Math.pow(2, x) + Math.ffloor(x) + Math.floor(x) + Std.int(x * 3) + Math.PI;
		var w = abs(v3) + sign(v3) + floor(v3) + ceil(v3) + fract(v3) + sqrt(v3) + inversesqrt(v3 + 1) + sin(v3) + cos(v3) + tan(v3) + exp(v3) + log(v3 + 1);
		w += min(v3, v3.zyx) + max(v3, 0.5 * v3) + pow(v3, vec3(2)) + step(v3, vec3(0.5)) + mix(v3, -v3, 0.5) + mix(v3, v3.yzx, v3);
		w += clamp(v3, 0, 1) + clamp(v3, v3.yzx, v3.zxy) + smoothstep(0, 1, v3) + smoothstep(vec3(0), vec3(1), v3) + reflect(v3, normalize(v3.zyx));
		w += cross(v3, v3.yzx) + vec3(dot(v3, v3), length(v3), distance(v3, v3.zyx)) + vec3(1, v2) + vec3(v2.yx, 1) + v3 / 2 - 1 / (v3 + 1) - 1;
		var n = 0, k = 7;
		while (n < 10) {
			n++;
			if (n == 3) continue;
			if (n > 8 || (k & 1 == 0 && n != 5)) break;
			k = (k << 1 | n) ^ (k >> 1);
		}
		var t = x > 0.5 ? x : -x;
		return vec4(w, s) * 0.01 + v4 * (n + k % 5 + t) + vec4(v2, v2) + vec4(x, v3) - vec4(x);
	}
}
