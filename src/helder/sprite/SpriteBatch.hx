package helder.sprite;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.image.Image;
import helder.sprite.Atlas.AtlasFrame;

// Textured quads on helder.gfx, batched: what a 2D game draws (Kha's
// graphics2, PixiJS's and Phaser's batchers, OpenFL's drawTiles), sprites
// of an atlas or parts of images, each moved, scaled, turned, faded and
// drawn over (alpha) or added (additive), in the order drawn; one draw a
// run of quads with the same texture (SpriteQuads), all in one vertex
// buffer, one pipeline (SpriteShader, premultiplied). Layers are the
// caller's order: draw the back first.
//
//   var batch = new SpriteBatch(device);
//   var sheet = batch.add(image);                     // uploaded once, premultiplied
//   batch.begin(width, height);                       // the target in drawing units, y down
//   batch.sprite(sheet, atlas.get("ship"), x, y, angle, 1, 1, 0.8);
//   batch.sprite(sheet, atlas.get("glow"), x, y, 0, 2, 2, 1, true);   // added
//   enc.beginPass(...); batch.flush(enc); enc.endPass();
//
// Nothing is allocated by a frame once the buffers have grown to it.
class SpriteBatch {
	public final device:Device;
	public final quads = new SpriteQuads();

	final pipeline:Pipeline;
	final sampler:Sampler;
	final textureSlot:Int;
	final viewBytes = Bytes.alloc(16);
	final textures:Array<Null<Texture>> = [];
	final sizes:Array<Int> = [];
	var buffer:Buffer;
	var capacity:Int;
	var indices:Null<Buffer> = null;
	var indexQuads = 0;
	var width = 1.0;
	var height = 1.0;

	// colorFormat: a render target's format (SpriteBox's RGBA8), null: the frame's
	public function new(device:Device, ?colorFormat:TextureFormat, samples = 1) {
		this.device = device;
		var d = SpriteShader.pipeline({blend: Premultiplied});
		if (colorFormat != null) d.colorFormat = colorFormat;
		if (samples > 1) d.samples = samples;
		pipeline = device.createPipeline(d);
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
		textureSlot = SpriteShader.textures[0].binding;
		capacity = quads.bytes.length;
		buffer = device.createBuffer({size: capacity, usage: Vertex});
	}

	// an image as a texture of the batch's (its pixels premultiplied): its id
	public function add(img:Image):SpriteTexture {
		var px = img.pixels, n = img.width * img.height;
		var pre = Bytes.alloc(n * 4);
		for (k in 0...n) {
			var a = px.get(4 * k + 3);
			pre.set(4 * k, Std.int((px.get(4 * k) * a + 127) / 255));
			pre.set(4 * k + 1, Std.int((px.get(4 * k + 1) * a + 127) / 255));
			pre.set(4 * k + 2, Std.int((px.get(4 * k + 2) * a + 127) / 255));
			pre.set(4 * k + 3, a);
		}
		var t = device.createTexture({width: img.width, height: img.height, format: RGBA8, data: pre});
		textures.push(t);
		sizes.push(img.width);
		sizes.push(img.height);
		return new SpriteTexture(textures.length - 1, img.width, img.height);
	}

	// frees a texture added
	public function remove(t:SpriteTexture) {
		var tex = textures[t.id];
		if (tex != null) device.destroyTexture(tex);
		textures[t.id] = null;
	}

	// a frame's drawing into a target of width x height units (x right, y down)
	public function begin(width:Float, height:Float) {
		this.width = width;
		this.height = height;
		quads.clear();
	}

	public inline function sprite(t:SpriteTexture, frame:AtlasFrame, x:Float, y:Float, rotation = 0.0, scaleX = 1.0, scaleY = 1.0, alpha = 1.0,
			additive = false)
		quads.sprite(t.id, t.width, t.height, frame, x, y, rotation, scaleX, scaleY, alpha, additive);

	public inline function image(t:SpriteTexture, sx:Float, sy:Float, sw:Float, sh:Float, x:Float, y:Float, w:Float, h:Float, alpha = 1.0,
			additive = false)
		quads.image(t.id, t.width, t.height, sx, sy, sw, sh, x, y, w, h, alpha, additive);

	// the quads drawn since begin, in the pass the encoder is in
	public function flush(enc:Encoder) {
		var n = quads.count;
		if (n == 0) return;
		var used = n * 4 * SpriteQuads.STRIDE;
		if (quads.bytes.length > capacity) {
			capacity = quads.bytes.length;
			device.destroyBuffer(buffer);
			buffer = device.createBuffer({size: capacity, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, quads.bytes, 0, used);
		if (n > indexQuads) {
			var q = indexQuads == 0 ? 1024 : indexQuads;
			while (q < n)
				q *= 2;
			var ib = Bytes.alloc(q * 6 * 4);
			for (k in 0...q) {
				var v = k * 4, o = k * 24;
				ib.setInt32(o, v);
				ib.setInt32(o + 4, v + 1);
				ib.setInt32(o + 8, v + 2);
				ib.setInt32(o + 12, v + 2);
				ib.setInt32(o + 16, v + 1);
				ib.setInt32(o + 20, v + 3);
			}
			if (indices != null) device.destroyBuffer(indices);
			indices = device.createBuffer({size: ib.length, usage: Index, data: ib});
			indexQuads = q;
		}
		// (units to clip space, y up)
		viewBytes.setFloat(0, 2 / width);
		viewBytes.setFloat(4, -2 / height);
		viewBytes.setFloat(8, -1);
		viewBytes.setFloat(12, 1);
		enc.setPipeline(pipeline);
		enc.setUniforms(SpriteShader.uniforms[0].binding, viewBytes);
		enc.setVertexBuffer(0, buffer);
		enc.setIndexBuffer(indices, UInt32);
		var runs = quads.runs, i = 0;
		while (i < runs.length) {
			var tex = textures[runs[i]];
			if (tex != null) {
				enc.setTexture(textureSlot, tex, sampler);
				enc.drawIndexed(runs[i + 2] * 6, 1, runs[i + 1] * 6, 0);
			}
			i += 3;
		}
	}

	public function dispose() {
		for (t in textures)
			if (t != null) device.destroyTexture(t);
		textures.resize(0);
		device.destroyBuffer(buffer);
		if (indices != null) device.destroyBuffer(indices);
		indices = null;
	}
}

// a texture of a SpriteBatch's (add)
class SpriteTexture {
	public final id:Int;
	public final width:Int;
	public final height:Int;

	public function new(id, width, height) {
		this.id = id;
		this.width = width;
		this.height = height;
	}
}
