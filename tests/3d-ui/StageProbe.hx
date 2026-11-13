import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// SurfaceTest's post stage (a <Scene hdr>'s setup adds it): the image so
// far with its green channel full, so a frame it ran over is marked
@:structInit @:publicFields class ProbeVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class ProbeVaryings {
	var clip:Vec4;
	var uv:Vec2;
}

final ProbeShader = shader({
	vertex: function(v:ProbeVertex):ProbeVaryings return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)},
	fragment: function(i:ProbeVaryings, p:{image:Texture2D}):Vec4 {
		var c = sample(p.image, i.uv);
		return vec4(c.x, 1, c.z, 1);
	}
});
