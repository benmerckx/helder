// title: Texture formats
// summary: Every portable texture format, written from bytes and rendered into, side by side; depth textures rendered and sampled
// tags: gfx, shaders, textures, render targets
// demo: canvas 512x384
import FormatsShader;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;

// The texture formats, in a window (Escape closes):
//
//   haxe -cp src -cp examples -main Formats
//     --custom-target hxmc=formats -D hxmc.libc=glibc
//
// (as Triangle.hx for macOS, Windows and the browser). A tile per format:
// R8, RG8, RGBA8, RGBA8Srgb, RGBA16F and R32F in the first row and a half,
// each the same 16x16 gradient (red across, green down, blue a half; R8 has
// red only, RG8 no blue) twice: on the left a texture written from bytes
// in the format's layout (TextureFormat.texelSize: bytes, half floats,
// floats; sRGB bytes encoded), on the right a render target of the format
// the gradient is drawn into, each frame, with a pipeline for it
// (PipelineDesc.colorFormat); both halves alike. Then Depth16 and Depth32F:
// a triangle's depth (0.1 to 0.9, the rest cleared to 1) rendered into a
// depth texture, then sampled, as grey. Every texture is read through a
// Nearest sampler (R32F and depth textures need one). The shaders are
// FormatsShader.hx.
class Formats {
	static inline var SIZE = 16;
	static final COLORS:Array<TextureFormat> = [R8, RG8, RGBA8, RGBA8Srgb, RGBA16F, R32F];
	static final DEPTHS:Array<TextureFormat> = [Depth16, Depth32F];

	final device:Device;
	final quads:Buffer;
	final indices:Buffer;
	final fill:Buffer;
	final triangle:Buffer;
	final tilePipeline:Pipeline;
	final nearest:Sampler;
	// per tile: the textures of its halves, the pass that renders one, its pipeline
	final left:Array<Texture> = [];
	final right:Array<Texture> = [];
	final passes:Array<PassDesc> = [];
	final pipelines:Array<Pipeline> = [];
	final colorTile = Bytes.alloc(16);
	final greyTile = Bytes.alloc(16);
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}]};

	public function new(device:Device) {
		this.device = device;
		var bytes = GradientShader.vertexBytes([for (c in [vec2(-1, -1), vec2(3, -1), vec2(-1, 3)]) {pos: c}]);
		fill = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		bytes = DepthShader.vertexBytes([{pos: vec3(-1, -1, 0.1)}, {pos: vec3(1, -1, 0.5)}, {pos: vec3(-1, 1, 0.9)}]);
		triangle = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		for (f in COLORS) {
			left.push(device.createTexture({width: SIZE, height: SIZE, format: f, data: gradient(f)}));
			var t = device.createTexture({width: SIZE, height: SIZE, format: f, renderTarget: true});
			right.push(t);
			passes.push({colors: [{load: Clear, texture: t}]});
			var d = GradientShader.pipeline();
			d.colorFormat = f;
			pipelines.push(device.createPipeline(d));
		}
		// (a depth texture's pass: a colour target as well, of its size)
		var scratch = device.createTexture({width: SIZE, height: SIZE, renderTarget: true});
		for (f in DEPTHS) {
			var t = device.createTexture({width: SIZE, height: SIZE, format: f});
			left.push(t);
			right.push(t);
			passes.push({colors: [{load: Clear, texture: scratch}], depth: {load: Clear, texture: t}});
			var d = DepthShader.pipeline({depthCompare: Always, depthWrite: true});
			d.colorFormat = RGBA8;
			d.depthFormat = f;
			pipelines.push(device.createPipeline(d));
		}
		// the tiles, 48 pixels square in a 256x192 frame (whole pixels: the
		// texels' edges fall between pixels), each two quads: the left half of
		// the left texture, the right half of the right one
		var vs:Array<TileVertex> = [];
		for (i in 0...8) {
			var x = 8 + (i % 4) * 60, y = 24 + (i >> 2) * 72;
			for (half in 0...2)
				for (c in [[0, 1], [1, 1], [1, 0], [0, 0]]) {
					var px = x + 24 * (half + c[0]), py = y + 48 * c[1];
					vs.push({pos: vec2(px / 128 - 1, 1 - py / 96), uv: vec2((half + c[0]) / 2, c[1])});
				}
		}
		bytes = TileShader.vertexBytes(vs);
		quads = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		var qi = Bytes.alloc(12);
		for (k in 0...6)
			qi.setUInt16(2 * k, [0, 1, 2, 0, 2, 3][k]);
		indices = device.createBuffer({size: qi.length, usage: Index, data: qi});
		tilePipeline = device.createPipeline(TileShader.pipeline());
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		TileShader.writeTile({grey: 0}, colorTile);
		TileShader.writeTile({grey: 1}, greyTile);
	}

	// the gradient's texels in the format: (x / 15, y / 15, 0.5, 1)
	static function gradient(f:TextureFormat):Bytes {
		var n = f.texelSize, b = Bytes.alloc(SIZE * SIZE * n);
		for (y in 0...SIZE)
			for (x in 0...SIZE) {
				var p = n * (y * SIZE + x), c = [x / 15, y / 15, 0.5, 1];
				switch f {
					case RGBA16F:
						for (k in 0...4)
							b.setUInt16(p + 2 * k, half(c[k]));
					case R32F:
						b.setFloat(p, c[0]);
					case _:
						for (k in 0...n)
							b.set(p + k, Math.round((f == RGBA8Srgb && k < 3 ? srgb(c[k]) : c[k]) * 255));
				}
			}
		return b;
	}

	// sRGB's encoding of a linear value
	static function srgb(v:Float):Float
		return v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;

	// a half float (binary16) of a value of 0 or 2^-14 and up, rounded
	static function half(v:Float):Int {
		var f = haxe.io.FPHelper.floatToI32(v), e = ((f >>> 23) & 0xff) - 112;
		return e <= 0 ? 0 : (e << 10) + (((f & 0x7fffff) + 0x1000) >> 13);
	}

	// records the frame's passes; the caller ends the frame
	public function draw(enc:Encoder) {
		for (i in 0...passes.length) {
			enc.beginPass(passes[i]);
			enc.setPipeline(pipelines[i]);
			enc.setVertexBuffer(0, i < COLORS.length ? fill : triangle);
			enc.draw(3);
			enc.endPass();
		}
		enc.beginPass(pass);
		enc.setPipeline(tilePipeline);
		enc.setVertexBuffer(0, quads);
		enc.setIndexBuffer(indices, UInt16);
		for (i in 0...8) {
			enc.setUniforms(0, i < COLORS.length ? colorTile : greyTile);
			enc.setTexture(1, left[i], nearest);
			enc.drawIndexed(6, 1, 0, 8 * i);
			enc.setTexture(1, right[i], nearest);
			enc.drawIndexed(6, 1, 0, 8 * i + 4);
		}
		enc.endPass();
	}

	static function main() {
		var window = new Window("Texture formats", 640, 480);
		var formats = new Formats(Device.create(window.surface));
		App.run(() -> {
			var enc = formats.device.beginFrame();
			if (enc == null) return;
			formats.draw(enc);
			formats.device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
