import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A vector constant, atan2 and arrays in a uniform block (the gfx lanes'
// palette frame, Palette.hx; ShaderTest: on the CPU and its text): four columns, each
// its colour of the palette by its index (read in the fragment stage, an
// index not known when compiling), times TINT; placed by the second of two
// matrices (the first all zeros: a wrong one draws nothing), coloured at
// all only if atan2 takes y first (atan2(1, 0) is a quarter turn)
final TINT = vec3(0.5, 1, 0.25);

@:structInit @:publicFields class PaletteVertex {
	var pos:Vec2;
	var index:Float;
}

@:structInit @:publicFields class PaletteVaryings {
	var pos:Vec4;
	var index:Float;
}

@:structInit @:publicFields class PaletteBlock {
	var scale:Vec4;
	@:length(4) var colors:Array<Vec4>;
	@:length(2) var turns:Array<Mat4>;
}

final PaletteShader = shader({
	vertex: function(v:PaletteVertex, p:{palette:PaletteBlock}):PaletteVaryings
		return {pos: position(p.palette.turns[1] * vec4(v.pos, 0, 1)), index: v.index},
	fragment: function(i:PaletteVaryings, p:{palette:PaletteBlock}):Vec4 {
		var k = Std.int(i.index + 0.5);
		var quarter = atan2(1, 0) * 2 / Math.PI;
		return vec4(p.palette.colors[k].xyz * TINT * (quarter * p.palette.scale.x), 1);
	}
});

// the palette (Palette's block)
final COLORS = [vec4(1, 0, 0, 1), vec4(0, 1, 0, 1), vec4(0, 0, 1, 1), vec4(1, 1, 1, 1)];
