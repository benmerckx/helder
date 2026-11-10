import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The painted finish, at the screen's own resolution and measured in
// points (pixels over the window's scale), so a phone and a 5K screen
// show the same picture: edges wander a little as a hand's would, the
// paint lies in soft bands of tone whose borders wander too, a brush's
// dabs and a paper's tooth lie over it, the darks are pulled towards
// indigo; between screens it fades into the mist. The last stage of
// PostProcess's chain (Afterglow: post.add).
@:structInit @:publicFields class FinishVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class FinishVaryings {
	var clip:Vec4;
}

@:structInit @:publicFields class FinishView {
	var size:Vec4; // xy: the frame's pixels, z: pixels a point, w: seconds
	var look:Vec4; // x: bands of tone, y: how far edges wander (points), z: the indigo's share, w: grain
	var fade:Vec4; // rgb: the mist faded into between screens, w: how far
}

final FinishShader = shader({
	vertex: function(v:FinishVertex):FinishVaryings
		return {clip: position(vec4(v.pos, 0, 1))},
	// noise: Afterglow's (it tiles): r, g two smooth noises, b a cloudier one, a a fine one
	fragment: function(i:FinishVaryings, p:{view:FinishView, frame:Texture2D, noise:Texture2D}):Vec4 {
		var k = p.view.size.z;
		var pt = i.clip.xy / k;
		// (a hand's edge: where the frame is read wanders)
		var slow = sample(p.noise, pt / 150), quick = sample(p.noise, pt / 47 + vec2(0.37, 0.61));
		var wander = (slow.xy - vec2(0.5)) * 2 + (quick.xy - vec2(0.5));
		var at = i.clip.xy + wander * (p.view.look.y * k);
		// (a stroke's smear along its way)
		var broad = sample(p.noise, vec2(pt.x / 900, pt.y / 260));
		var way = broad.x * 6.2832;
		var along = vec2(cos(way), sin(way)) * (0.55 * k);
		var c = sample(p.frame, at / p.view.size.xy).xyz * 0.5 + sample(p.frame, (at + along) / p.view.size.xy).xyz * 0.25
			+ sample(p.frame, (at - along) / p.view.size.xy).xyz * 0.25;
		// (paint in soft bands of tone, their borders wandering)
		var lum = max(dot(c, vec3(0.3, 0.5, 0.2)), 0.0001);
		var levels = p.view.look.x;
		var shift = sample(p.noise, pt / 350 + vec2(0.13, 0.71)).z * 1.6;
		var v = sqrt(lum) * levels + shift;
		var banded = (floor(v) + smoothstep(0.25, 0.75, fract(v)) - shift) / levels;
		c *= mix(1.0, max(banded, 0) * max(banded, 0) / lum, 0.7);
		// (the brush's dabs, short strokes across; the paper's tooth)
		var tooth = sample(p.noise, pt / 256).w * 0.6 + quick.w * 0.4;
		c *= 1 + ((broad.z - 0.5) * 0.5 + (tooth - 0.5)) * p.view.look.w * (1 - 0.6 * smoothstep(0.3, 0.9, lum));
		lum = dot(c, vec3(0.3, 0.5, 0.2));
		c += vec3(0.07, 0.05, 0.17) * (pow(1 - clamp(lum, 0, 1), 4) * p.view.look.z);
		c = mix(c, p.view.fade.xyz, p.view.fade.w);
		// (the 8 bits' own steps broken up, a pixel's worth)
		c += vec3((sample(p.noise, i.clip.xy / 256).w - 0.5) / 255);
		return vec4(c, 1);
	}
});
