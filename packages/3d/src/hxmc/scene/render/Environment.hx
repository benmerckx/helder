package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.math.MathTools;
import hxmc.scene.render.EnvironmentShader;

// An environment, opted in (renderer.use(new Environment(device,
// texture))): an equirectangular image (longitude across, latitude down;
// sRGB, mip-mapped) drawn behind the scene (at the renderer's BeforeOpaque
// point, as the sky) and lighting it: the standard material's ambient
// from it, diffuse from a small mip level along the normal, specular
// along the reflection from a level by roughness (mip levels standing in
// for a filtered map: a cheap image-based light). A program without one
// keeps the sky-and-ground ambient and links none of this.
//   var env = Environment.fromImage(device, "image/png", Asset.embed("sky.png")); // with Images.decode set
class Environment implements RenderFeature {
	public final device:Device;
	public final texture:Texture;
	// the mip levels below the first (the map's width 2^levels)
	public final levels:Int;
	// how bright the environment is, as light (1: its colours)
	public var intensity = 1.0;
	// whether it is drawn behind the scene (false: it only lights it)
	public var background = true;

	final pipeline:Pipeline;
	final quad:Buffer;
	final sampler:Sampler;
	final bytes = Bytes.alloc(EnvironmentShader.uniforms[0].size);

	// texture: mip-mapped (mipmapped's), width twice its height
	public function new(device:Device, texture:Texture, width:Int) {
		this.device = device;
		this.texture = texture;
		var l = 0;
		while ((1 << (l + 1)) <= width)
			l++;
		levels = l;
		pipeline = device.createPipeline(EnvironmentShader.pipeline());
		var v = EnvironmentShader.vertexBytes([
			{pos: new hxmc.gfx.shader.Vec2(-1, -1)}, {pos: new hxmc.gfx.shader.Vec2(1, -1)}, {pos: new hxmc.gfx.shader.Vec2(-1, 1)},
			{pos: new hxmc.gfx.shader.Vec2(-1, 1)}, {pos: new hxmc.gfx.shader.Vec2(1, -1)}, {pos: new hxmc.gfx.shader.Vec2(1, 1)}
		]);
		quad = device.createBuffer({size: v.length, usage: Vertex, data: v});
		sampler = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
	}

	// an encoded image's environment (Images.decode must read it); null when it cannot
	public static function fromImage(device:Device, mime:String, bytes:Bytes):Null<Environment> {
		if (Images.decode == null) return null;
		var image = Images.decode(mime, bytes);
		if (image == null) return null;
		return new Environment(device, mipmapped(device, image.width, image.height, image.rgba), image.width);
	}

	// an RGBA8 image's texture with its mip levels made here (2x2 boxes,
	// down to 1x1): the same texels on every GPU, whose own mip making
	// differs, and this image's small levels are its light
	public static function mipmapped(device:Device, width:Int, height:Int, rgba:Bytes):Texture {
		var t = device.createTexture({width: width, height: height, data: rgba, mipLevels: 0});
		var w = width, h = height, level = 0, src = rgba;
		while (w > 1 || h > 1) {
			var nw = w > 1 ? w >> 1 : 1, nh = h > 1 ? h >> 1 : 1;
			var dst = Bytes.alloc(nw * nh * 4);
			for (y in 0...nh)
				for (x in 0...nw) {
					var x0 = w > 1 ? 2 * x : 0, y0 = h > 1 ? 2 * y : 0, x1 = w > 1 ? x0 + 1 : x0, y1 = h > 1 ? y0 + 1 : y0;
					for (c in 0...4) {
						var sum = src.get(4 * (y0 * w + x0) + c) + src.get(4 * (y0 * w + x1) + c) + src.get(4 * (y1 * w + x0) + c) + src.get(4 * (y1 * w + x1) + c);
						dst.set(4 * (y * nw + x) + c, (sum + 2) >> 2);
					}
				}
			level++;
			device.writeTexture(t, dst, 0, 0, nw, nh, 0, level);
			w = nw;
			h = nh;
			src = dst;
		}
		return t;
	}

	public function attach(renderer:Renderer) {
		@:privateAccess renderer.environment = this;
		renderer.inject(BeforeOpaque, (enc, frame) -> if (background) draw(enc, frame, renderer));
	}

	// (the standard material's binding)
	@:allow(hxmc.scene.render.Renderer) function bind(enc:Encoder, slot:Int)
		enc.setTexture(slot, texture, sampler);

	function draw(enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		var e = frame.eye;
		EnvironmentShader.writeEnvironmentParams({
			invViewProj: MathTools.inverse(frame.viewProj),
			eye: new Vec4(e.x, e.y, e.z, 1),
			params: new Vec4(intensity * renderer.exposure, 0, 0, 0)
		}, bytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, bytes);
		enc.setTexture(EnvironmentShader.textures[0].binding, texture, sampler);
		enc.setVertexBuffer(0, quad);
		enc.draw(6);
	}

	public function dispose() {
		device.destroyTexture(texture);
		device.destroyBuffer(quad);
	}
}
