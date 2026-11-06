// A texture is a parameter, passed on: not a local.
// expect: ShaderTextureLocal.hx:18: characters 3-17
// expect: t: a texture is a parameter, not a local
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))},
	fragment: function(o:O, p:{tex:Texture2D}):Vec4 {
		var t = p.tex;
		return sample(t, o.pos.xy);
	}
});

class ShaderTextureLocal {
	static function main()
		trace(S.vertexCode);
}
