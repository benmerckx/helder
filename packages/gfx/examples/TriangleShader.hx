import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The triangle's shaders (Triangle.hx): the vertex type is also what the
// CPU writes into the vertex buffer (vertexBytes), and both stages run as
// ordinary Haxe too (packages/gfx/test/ShaderTest.hx).
@:structInit @:publicFields class Vertex {
	var pos:Vec2;
	var color:Vec3;
}

@:structInit @:publicFields class Varyings {
	@:position var pos:Vec4;
	var color:Vec3;
}

class TriangleShader implements Shaders {
	@:vertex static function vs(v:Vertex):Varyings
		return {pos: vec4(v.pos, 0, 1), color: v.color};

	@:fragment static function fs(i:Varyings):Vec4
		return vec4(i.color, 1);
}
