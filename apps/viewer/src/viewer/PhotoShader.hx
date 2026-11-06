package viewer;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The image on the view: a quad at the camera's rectangle (clip space),
// the image's texture read as linear light (RGBA8Srgb: filtered and its
// mip levels averaged in linear light), over the background in linear
// light, written back as sRGB into an RGBA8 target that ui shows as it is.
@:structInit @:publicFields class PhotoVertex {
	var corner:Vec2; // 0..1
}

@:structInit @:publicFields class PhotoVaryings {
	var pos:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class PhotoView {
	// the quad's left, top, right and bottom in clip space
	var rect:Vec4;
	// its texture coordinates: left, top, right, bottom (a tile's part of its texture)
	var uv:Vec4;
	// the background, linear
	var background:Vec4;
}

final PhotoShader = shader({
	vertex: function(v:PhotoVertex, view:PhotoView):PhotoVaryings
		return {pos: position(vec4(mix(view.rect.x, view.rect.z, v.corner.x), mix(view.rect.y, view.rect.w, v.corner.y), 0, 1)), uv: vec2(mix(view.uv.x, view.uv.z, v.corner.x), mix(view.uv.y, view.uv.w, v.corner.y))},
	fragment: function(i:PhotoVaryings, view:PhotoView, image:Texture2D):Vec4 {
		var c = sample(image, i.uv);
		var rgb = mix(view.background.xyz, c.xyz, c.w);
		// (linear to sRGB, the exact curve)
		var lo = rgb * 12.92;
		var hi = pow(rgb, vec3(1 / 2.4, 1 / 2.4, 1 / 2.4)) * 1.055 - vec3(0.055, 0.055, 0.055);
		return vec4(mix(lo, hi, step(vec3(0.0031308, 0.0031308, 0.0031308), rgb)), 1);
	}
});
