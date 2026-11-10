import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The poststage frame's own stages (Scenes, PostProcess.add): a sepia
// grade, then scanlines (bands of 8 pixels, the image read Nearest by its
// pixels: the fragment's position), the last into the frame
@:structInit @:publicFields class StageVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class StageVaryings {
	var clip:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class StageParams {
	var size:Vec4; // xy: the image's pixels, z: a band's pixels, w: the sepia's share
}

function fullscreen(v:StageVertex):StageVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

final SepiaShader = shader({
	vertex: function(v:StageVertex):StageVaryings return fullscreen(v),
	fragment: function(i:StageVaryings, p:{stage:StageParams, image:Texture2D}):Vec4 {
		var c = sample(p.image, i.uv);
		var y = dot(c.xyz, vec3(0.3, 0.59, 0.11));
		return vec4(mix(c.xyz, vec3(y * 1.1, y * 0.9, y * 0.7), p.stage.size.w), c.w);
	}
});

final ScanShader = shader({
	vertex: function(v:StageVertex):StageVaryings return fullscreen(v),
	fragment: function(i:StageVaryings, p:{stage:StageParams, image:Texture2D}):Vec4 {
		var c = sample(p.image, i.clip.xy / p.stage.size.xy);
		var dark = fract(i.clip.y / p.stage.size.z) < 0.5 ? 1.0 : 0.55;
		return vec4(c.xyz * dark, c.w);
	}
});
