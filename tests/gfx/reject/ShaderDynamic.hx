// Dynamic has no shader type.
// expect: ShaderDynamic.hx:18: characters 3-23
// expect: Dynamic is not a shader type
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
	fragment: function(o:O):Vec4 {
		var d:Dynamic = 0.5;
		return o.pos * (d : Float);
	}
});

class ShaderDynamic {
	static function main()
		trace(S.fragmentCode);
}
