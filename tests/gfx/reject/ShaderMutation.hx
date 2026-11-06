// Shader values are immutable (a struct is copied on the GPU, shared on the CPU): assigning to a field is an error.
// expect: ShaderMutation.hx:18: characters 3-8
// expect: shader values are immutable: assign to a local, not to a field
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V):O {
		var m:O = {pos: position(vec4(v.pos, 0, 1))};
		m.pos = vec4(0);
		return m;
	},
	fragment: function(m:O):Vec4 return m.pos
});

class ShaderMutation {
	static function main()
		trace(S.vertexCode);
}
