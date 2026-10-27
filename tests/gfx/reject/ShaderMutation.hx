// Shader values are immutable (a struct is copied on the GPU, shared on the CPU): assigning to a field is an error.
// expect: ShaderMutation.hx:22: characters 3-8
// expect: shader: shader values are immutable: assign to a local, not to a field
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

@:structInit @:publicFields class M {
	@:position var pos:Vec4;
}

class ShaderMutation implements Shaders {
	@:vertex static function vs(v:V):M {
		var m:M = {pos: vec4(v.pos, 0, 1)};
		m.pos = vec4(0);
		return m;
	}

	@:fragment static function fs(m:M):Vec4
		return m.pos;

	static function main()
		trace(vertexCode);
}
