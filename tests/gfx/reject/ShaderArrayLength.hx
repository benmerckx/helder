// An array field without its length (@:length(n)): the error at the field.
// expect: ShaderArrayLength.hx:12: characters 2-25
// expect: an array field has a length, @:length(n)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class B {
	var lights:Array<Vec4>;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V, p:{b:B}):O return {pos: position(p.b.lights[0] + vec4(v.pos, 0, 1))},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderArrayLength {
	static function main()
		trace(S.vertexCode);
}
