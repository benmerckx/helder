import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.ShaderMath.*;
import PaletteShader;

// The palette frame (PaletteShader): four columns, EXPECTED their pixels
class Palette {
	public static final EXPECTED:Array<Array<Float>> = [[0.5, 0, 0], [0, 1, 0], [0, 0, 0.25], [0.5, 1, 0.25]];

	final quad:Buffer;
	final pipeline:Pipeline;
	final bytes = Bytes.alloc(PaletteShader.uniforms[0].size);
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.125, 0.125, 0.125)}]};

	public function new(device:Device) {
		var data = PaletteShader.vertexBytes([
			for (k in 0...4) {
				var x0 = -1 + k * 0.5, x1 = x0 + 0.5;
				for (p in [[x0, -0.5], [x1, -0.5], [x1, 0.5], [x0, -0.5], [x1, 0.5], [x0, 0.5]])
					({pos: vec2(p[0], p[1]), index: k} : PaletteVertex);
			}
		]);
		quad = device.createBuffer({size: data.length, usage: Vertex, data: data});
		pipeline = device.createPipeline(PaletteShader.pipeline());
		PaletteShader.params.palette.write({scale: vec4(1), colors: COLORS, turns: [mat4(0), mat4(1)]}, bytes);
	}

	public function draw(enc:Encoder) {
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(PaletteShader.params.palette.block.binding, bytes);
		enc.setVertexBuffer(0, quad);
		enc.draw(24);
		enc.endPass();
	}

	// each column's middle pixel against EXPECTED: null, or what differs
	public static function check(pixels:Bytes, width:Int, height:Int):Null<String> {
		var wrong = [];
		for (k in 0...4) {
			var x = Std.int((k + 0.5) * width / 4), y = Std.int(height / 2), at = 4 * (y * width + x);
			var got = [for (c in 0...3) pixels.get(at + c)];
			var want = [for (v in EXPECTED[k]) Math.round(v * 255)];
			for (c in 0...3)
				if (Math.abs(got[c] - want[c]) > 2) {
					wrong.push('colour $k: $got, not $want');
					break;
				}
		}
		return wrong.length == 0 ? null : wrong.join("; ");
	}
}
