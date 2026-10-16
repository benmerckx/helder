// The vertex stage's output has one @:position (the clip-space position).
// expect: ShaderPosition.hx:20: lines 20-21
// expect: shader: @:vertex vs: NoPosition needs exactly one @:position field (it has 0)
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

@:structInit @:publicFields class NoPosition {
	var color:Vec4;
}

class ShaderPosition implements Shaders {
	@:vertex static function vs(v:V):NoPosition
		return {color: vec4(v.pos, 0, 1)};

	@:fragment static function fs(o:NoPosition):Vec4
		return o.color;

	static function main()
		trace(vertexCode);
}
