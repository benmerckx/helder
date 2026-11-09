import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import PaintShader.fog;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Still black water: the ruins mirrored (Afterglow's reflection pass,
// the scene drawn upside down into a smaller target) read at the
// fragment's place, stirred by slow ripples and smeared downwards as a
// painter would, dark where it faces the eye, a mirror at a glance.
@:structInit @:publicFields class WaterVertex {
	var pos:Vec3;
}

@:structInit @:publicFields class WaterVaryings {
	var clip:Vec4;
	var world:Vec3;
}

@:structInit @:publicFields class WaterView {
	var viewProj:Mat4;
	var eye:Vec4; // w: seconds
	var size:Vec4; // xy: the target's pixels; z: the mist's density
}

final WaterShader = shader({
	vertex: function(v:WaterVertex, p:{view:WaterView}):WaterVaryings
		return {clip: position(p.view.viewProj * vec4(v.pos, 1)), world: v.pos},
	fragment: function(i:WaterVaryings, p:{view:WaterView, mirror:Texture2D}):Vec4 {
		var toEye = p.view.eye.xyz - i.world;
		var dist = length(toEye);
		var dir = -toEye / dist;
		var t = p.view.eye.w;
		var w = i.world.xz;
		var rx = noise2(vec2(w.x * 1.3 + t * 0.15, w.y * 5.0 - t * 0.2)) - 0.5;
		var ry = noise2(vec2(w.x * 0.9 - t * 0.1, w.y * 3.0 + t * 0.12)) - 0.5;
		var stir = vec2(rx, ry) * (0.03 / (1 + dist * 0.08));
		var uv = i.clip.xy / p.view.size.xy + stir;
		var px = 1 / p.view.size.y;
		var seen = sample(p.mirror, uv).xyz * 0.4 + sample(p.mirror, uv + vec2(0, px * 2)).xyz * 0.3 + sample(p.mirror, uv + vec2(0, px * 5)).xyz * 0.2
			+ sample(p.mirror, uv + vec2(0, px * 9)).xyz * 0.1;
		var glance = pow(1 - abs(dir.y), 3);
		var deep = vec3(0.004, 0.008, 0.02);
		var c = deep + seen * (0.18 + 0.72 * glance);
		return vec4(mix(c, fog(dir, smoothstep(14, 45, dist)) * 0.85, haze(dist, 0, p.view.size.z)), 1);
	}
});
