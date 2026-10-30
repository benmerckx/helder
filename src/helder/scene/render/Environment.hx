package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.EnvironmentShader;

// An environment, opted in (renderer.use(new Environment(device,
// texture))): an equirectangular image (longitude across, latitude down;
// sRGB, mip-mapped) drawn behind the scene (at the renderer's BeforeOpaque
// point, as the sky) and lighting it: the standard material's ambient
// from it, diffuse from a small mip level along the normal, specular
// along the reflection from a level by roughness (mip levels standing in
// for a filtered map: a cheap image-based light). A program without one
// keeps the sky-and-ground ambient and links none of this.
//   var env = Environment.fromImage(device, "image/png", helder.asset.Asset.embed("sky.png")); // with Images.decode set (Images.png)
//
// Prefiltered (Environment.prefiltered): the light filtered once ahead,
// image-based lighting proper. An atlas of levels + 1 rows, each the whole
// sphere (equirectangular, width by width / 2): row k the specular light
// for a roughness of k / (levels - 1) (the environment convolved with
// GGX's lobe, the split sum's first half), the last the diffuse
// irradiance (cosine weighted, over pi); the material reads two rows by
// its roughness, blended, and the last along its normal. Small (128 x 448
// for 6 levels: 224 KB on the GPU), made by a tool once (Expansion's
// tools/envbake.py), no mips; the decoded pixels freed after the upload.
//   var env = Environment.prefiltered(device, "image/png", bytes, 6);
class Environment implements RenderFeature {
	public final device:Device;
	public final texture:Texture;
	// the mip levels below the first (the map's width 2^levels)
	public final levels:Int;
	// how bright the environment is, as light (1: its colours)
	public var intensity = 1.0;
	// whether it is drawn behind the scene (false: it only lights it)
	public var background = true;
	// a prefiltered atlas's levels of roughness (0: a mip-mapped image)
	public final rows:Int;
	// (half a texel of an atlas's row, in its rows' v)
	final edge:Float;

	var pipeline:Pipeline = cast 0; // (the renderer's, when attached)
	final quad:Buffer;
	final sampler:Sampler;
	// (an atlas's: one level)
	final flat:Sampler;
	final bytes = Bytes.alloc(EnvironmentShader.uniforms[0].size);

	// texture: mip-mapped (Images.mipmapped's), width twice its height; or
	// a prefiltered atlas of rows levels (prefiltered), width its width
	public function new(device:Device, texture:Texture, width:Int, rows = 0) {
		this.device = device;
		this.texture = texture;
		this.rows = rows;
		edge = 1 / width;
		var l = 0;
		while ((1 << (l + 1)) <= width)
			l++;
		levels = l;
		var v = EnvironmentShader.vertexBytes([
			{pos: new helder.gfx.shader.Vec2(-1, -1)}, {pos: new helder.gfx.shader.Vec2(1, -1)}, {pos: new helder.gfx.shader.Vec2(-1, 1)},
			{pos: new helder.gfx.shader.Vec2(-1, 1)}, {pos: new helder.gfx.shader.Vec2(1, -1)}, {pos: new helder.gfx.shader.Vec2(1, 1)}
		]);
		quad = device.createBuffer({size: v.length, usage: Vertex, data: v});
		sampler = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
		flat = device.createSampler({filter: Linear, wrap: Repeat});
	}

	// an encoded image's environment (Images.decode must read it); null when it cannot
	public static function fromImage(device:Device, mime:String, bytes:Bytes):Null<Environment> {
		if (Images.decode == null) return null;
		var image = Images.decode(mime, bytes);
		if (image == null) return null;
		return new Environment(device, Images.mipmapped(device, image.width, image.height, image.rgba), image.width);
	}

	// a prefiltered atlas's environment (levels rows of roughness and the
	// irradiance's, each width by width / 2; Images.decode must read it); null when it cannot
	public static function prefiltered(device:Device, mime:String, bytes:Bytes, levels:Int):Null<Environment> {
		if (Images.decode == null) return null;
		var image = Images.decode(mime, bytes);
		if (image == null) return null;
		if (image.height != (levels + 1) * (image.width >> 1)) throw "helder.scene: Environment.prefiltered: an atlas of " + (levels + 1) + " rows of " + image.width + " x " + (image.width >> 1) + " expected, not " + image.width + " x " + image.height;
		var t = device.createTexture({width: image.width, height: image.height, data: image.rgba});
		return new Environment(device, t, image.width, levels);
	}

	public function attach(renderer:Renderer) {
		pipeline = renderer.createPipeline(EnvironmentShader.pipeline());
		@:privateAccess renderer.environment = this;
		renderer.inject(BeforeOpaque, (enc, frame) -> if (background) draw(enc, frame, renderer));
	}

	// (the standard material's binding)
	@:allow(helder.scene.render.Renderer) function bind(enc:Encoder, slot:Int)
		enc.setTexture(slot, texture, rows > 0 ? flat : sampler);

	function draw(enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		var e = frame.eye;
		EnvironmentShader.writeEnvironmentParams({
			invViewProj: MathTools.inverse(frame.viewProj),
			eye: new Vec4(e.x, e.y, e.z, 1),
			params: new Vec4(intensity * renderer.exposure, frame.hdr ? 1 : 0, rows, edge)
		}, bytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, bytes);
		enc.setTexture(EnvironmentShader.textures[0].binding, texture, rows > 0 ? flat : sampler);
		enc.setVertexBuffer(0, quad);
		enc.draw(6);
	}

	public function dispose() {
		device.destroyTexture(texture);
		device.destroyBuffer(quad);
	}
}
