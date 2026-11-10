import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class BlendVertex {
	var pos:Vec2;
	var color:Vec4;
}

@:structInit @:publicFields class BlendVaryings {
	var pos:Vec4;
	var color:Vec4;
}

final BlendShader = shader({
	vertex: function(v:BlendVertex):BlendVaryings return {pos: position(vec4(v.pos, 0, 1)), color: v.color},
	fragment: function(i:BlendVaryings):Vec4 return i.color
});

// The blend modes (the gfx lanes' blend scene): over a grey of 0.125, a
// colour of (0.5, 0.25, 0) at alpha 0.5 in four columns, Alpha, Additive,
// Premultiplied and Multiply; EXPECTED their pixels (8 bits), checked as
// they are besides the golden image (an Additive that weighs by alpha
// passes a golden image blessed with it)
class Blending {
	public static final MODES:Array<Blend> = [Alpha, Additive, Premultiplied, Multiply];
	static final NAMES = ["Alpha", "Additive", "Premultiplied", "Multiply"];
	public static final EXPECTED = [[0.3125, 0.1875, 0.0625], [0.625, 0.375, 0.125], [0.5625, 0.3125, 0.0625], [0.0625, 0.03125, 0]];

	final quad:Buffer;
	final pipelines:Array<Pipeline>;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.125, 0.125, 0.125)}]};

	public function new(device:Device) {
		var c = vec4(0.5, 0.25, 0, 0.5);
		var bytes = BlendShader.vertexBytes([
			for (k in 0...4) {
				var x0 = -1 + k * 0.5, x1 = x0 + 0.5;
				for (p in [[x0, -0.5], [x1, -0.5], [x1, 0.5], [x0, -0.5], [x1, 0.5], [x0, 0.5]])
					({pos: vec2(p[0], p[1]), color: c} : BlendVertex);
			}
		]);
		quad = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		pipelines = [for (b in MODES) device.createPipeline(BlendShader.pipeline({blend: b}))];
	}

	public function draw(enc:Encoder) {
		enc.beginPass(pass);
		enc.setVertexBuffer(0, quad);
		for (k in 0...4) {
			enc.setPipeline(pipelines[k]);
			enc.draw(6, 1, k * 6);
		}
		enc.endPass();
	}

	// the column's middle pixel of each mode against EXPECTED: null, or what differs
	public static function check(pixels:Bytes, width:Int, height:Int):Null<String> {
		var wrong = [];
		for (k in 0...4) {
			var x = Std.int((k + 0.5) * width / 4), y = Std.int(height / 2), at = 4 * (y * width + x);
			var got = [for (c in 0...3) pixels.get(at + c)];
			var want = [for (v in EXPECTED[k]) Math.round(v * 255)];
			for (c in 0...3)
				if (Math.abs(got[c] - want[c]) > 2) {
					wrong.push('${NAMES[k]}: $got, not $want');
					break;
				}
		}
		return wrong.length == 0 ? null : wrong.join("; ");
	}
}
