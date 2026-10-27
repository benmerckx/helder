import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A shader with uniform blocks and helpers from another module
// (Lighting.hx), for the shader macro's tests (ShaderTest: run on the CPU,
// the emitted source against test/shader/; GfxTest and WebTest: compiled
// by each back end).
@:structInit @:publicFields class LitVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
}

@:structInit @:publicFields class LitVaryings {
	var normal:Vec3;
	@:position var clip:Vec4;
	var uv:Vec2;
	var shade:Float;
}

@:structInit @:publicFields class Camera {
	var viewProj:Mat4;
	var eye:Vec3;
	var time:Float;
}

@:structInit @:publicFields class Material {
	var tint:Vec4;
	var steps:Int;
}

class LitShader implements Shaders {
	static final WOBBLE = 0.05;

	@:vertex static function vs(v:LitVertex, cam:Camera):LitVaryings {
		var clip = cam.viewProj * vec4(v.pos, 1);
		var wobble = sin(cam.time + v.pos.x * 3) * WOBBLE;
		return {
			normal: v.normal,
			clip: clip + vec4(wobble, 0, 0, 0),
			uv: v.uv.yx,
			shade: Lighting.lambert(v.normal, cam.eye - v.pos)
		};
	}

	@:fragment static function fs(i:LitVaryings, m:Material):Vec4 {
		var glow = 0.0;
		for (k in 0...m.steps)
			glow += 1 / (k + 2);
		var color = m.tint.xyz * (Lighting.AMBIENT + Lighting.posterize(i.shade, m.steps));
		if (i.uv.x > 0.5) color = color.zyx else if (i.uv.y < 0.25) color = 1 - color;
		var check = Std.int(i.uv.x * 8) % 2 == 0 ? 1.0 : 0.5;
		return vec4(clamp(color * check + glow * 0.01, 0, 1), m.tint.w);
	}
}
