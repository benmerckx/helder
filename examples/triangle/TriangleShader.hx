import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The triangle's shaders (Triangle.hx): the vertex type is also what the
// CPU writes into the vertex buffer (vertexBytes), and both stages run as
// ordinary Haxe too (tests/gfx/ShaderTest.hx).
@:structInit @:publicFields class Vertex {
	var pos:Vec2;
	var color:Vec3;
}

@:structInit @:publicFields class Varyings {
	var pos:Vec4;
	var color:Vec3;
}

final TriangleShader = shader({
	vertex: function(v:Vertex):Varyings return {pos: position(vec4(v.pos, 0, 1)), color: v.color},
	fragment: function(i:Varyings):Vec4 return vec4(i.color, 1)
});
