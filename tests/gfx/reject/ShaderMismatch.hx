// The fragment stage takes what the vertex stage returns.
// expect: ShaderMismatch.hx:24: lines 24-25
// expect: shader: stage interface mismatch: @:fragment fs takes Other, but @:vertex vs returns O
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

@:structInit @:publicFields class Other {
	@:position var pos:Vec4;
	var color:Vec3;
}

class ShaderMismatch implements Shaders {
	@:vertex static function vs(v:V):O
		return {pos: vec4(v.pos, 0, 1)};

	@:fragment static function fs(o:Other):Vec4
		return vec4(o.color, 1);

	static function main()
		trace(vertexCode);
}
