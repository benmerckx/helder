import Mood.noise2;
import MothShader.MothView;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Shafts of pale light falling through the mist between the planes: each
// a quad turned about its own upright towards the eye, soft across,
// streaked along, fading in at the top and out over the water (additive)
@:structInit @:publicFields class BeamVertex {
	var corner:Vec2;
	var at:Vec4; // xyz: its foot, w: its width
	var shape:Vec4; // x: its height, y: its slant (x over height), z: a seed, w: its strength
}

@:structInit @:publicFields class BeamVaryings {
	var clip:Vec4;
	var q:Vec2;
	var shape:Vec4;
}

final BeamShader = shader({
	vertex: function(v:BeamVertex, p:{view:MothView}):BeamVaryings {
		var across = normalize(vec3(p.view.right.x, 0, p.view.right.z));
		var up = v.corner.y * 0.5 + 0.5;
		var w = v.at.xyz + across * (v.corner.x * v.at.w * (0.7 + 0.6 * up)) + vec3(v.shape.y * up * v.shape.x, up * v.shape.x, 0);
		return {clip: position(p.view.viewProj * vec4(w, 1)), q: vec2(v.corner.x, up), shape: v.shape};
	},
	fragment: function(i:BeamVaryings, p:{view:MothView}):Vec4 {
		var t = p.view.up.w, seed = i.shape.z;
		var soft = exp(-i.q.x * i.q.x * 4) * (1 - i.q.x * i.q.x);
		var streak = 0.55 + 0.45 * noise2(vec2(i.q.x * 3 + seed * 7, i.q.y * 2 - t * 0.04));
		var fade = smoothstep(1.0, 0.55, i.q.y) * smoothstep(0.0, 0.3, i.q.y);
		var a = soft * streak * fade * i.shape.w;
		return vec4(vec3(0.05, 0.1, 0.16) * a, 0);
	}
});
