import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.ShaderMath.*;

// What a UI renderer needs of hxmc.gfx, drawn in one frame (GfxTest
// features, WebTest): vertices written into a buffer created empty
// (writeBuffer), an R8 mask sampled with Nearest and partly rewritten
// (writeTexture), an RGBA8 image sampled with Linear, premultiplied
// blending, and a scissor rectangle. Texel edges fall between pixel
// centres, so that Nearest sampling is the same on every rasterizer.
class FeatureScene {
	public static inline var WIDTH = 256;
	public static inline var HEIGHT = 192;

	final device:Device;
	final pipeline:Pipeline;
	final vertices:Buffer;
	final mask:Texture;
	final image:Texture;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}]};
	var count = 0;

	public function new(device:Device) {
		this.device = device;
		pipeline = device.createPipeline(FeatureShader.pipeline({blend: Premultiplied}));
		vertices = device.createBuffer({size: 64 * 1024, usage: Vertex});
		// an 8x8 checker, its top left 2x2 then written white
		var m = Bytes.alloc(64);
		for (y in 0...8)
			for (x in 0...8)
				m.set(y * 8 + x, (x + y) & 1 == 0 ? 255 : 40);
		mask = device.createTexture({width: 8, height: 8, format: R8, filter: Nearest, data: m});
		var white = Bytes.alloc(4);
		white.fill(0, 4, 255);
		device.writeTexture(mask, 0, 0, 2, 2, white);
		// a 2x2 image: red, green / blue, white
		var im = Bytes.ofHex("ff0000ff00ff00ff0000ffffffffffff");
		image = device.createTexture({width: 2, height: 2, format: RGBA8, filter: Linear, data: im});
	}

	public function draw(enc:Encoder) {
		var vs:Array<FeatureShader.FeatureVertex> = [];
		// the image (linear, tinted white), the mask's coverage in yellow
		quad(vs, 16, 16, 64, 64, 0, 0, 1, 1, [1, 1, 1, 1], 2);
		quad(vs, 96, 16, 64, 64, 0, 0, 1, 1, [1, 1, 0, 1], 1);
		// a translucent red bar over both (premultiplied: 0.5 alpha)
		quad(vs, 8, 56, 168, 16, 0, 0, 0, 0, [0.5, 0, 0, 0.5], 0);
		var first = vs.length;
		// a green quad over the whole target, scissored to a rectangle
		quad(vs, 0, 0, WIDTH, HEIGHT, 0, 0, 0, 0, [0, 0.8, 0.2, 1], 0);
		var bytes = FeatureShader.vertexBytes(vs);
		device.writeBuffer(vertices, 0, bytes);
		count = vs.length;
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, vertices);
		enc.setTexture(0, mask);
		enc.setTexture(1, image);
		enc.draw(first);
		enc.setScissor(184, 24, 48, 40);
		enc.draw(count - first, 1, first);
		enc.setScissor(0, 0, WIDTH, HEIGHT);
		enc.endPass();
	}

	// two triangles of a w x h rectangle at (x, y), in pixels from the top left
	static function quad(vs:Array<FeatureShader.FeatureVertex>, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float,
			c:Array<Float>, mode:Float) {
		function v(px:Float, py:Float, u:Float, t:Float):FeatureShader.FeatureVertex
			return {
				pos: vec2(px / WIDTH * 2 - 1, 1 - py / HEIGHT * 2),
				uv: vec2(u, t),
				color: vec4(c[0], c[1], c[2], c[3]),
				mode: mode
			};
		var a = v(x, y, u0, v0), b = v(x + w, y, u1, v0), d = v(x, y + h, u0, v1), e = v(x + w, y + h, u1, v1);
		for (p in [a, d, b, b, d, e])
			vs.push(p);
	}
}
