package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.scene.render.PostShader;
import helder.scene.render.PbrShader.aces;
import helder.scene.render.PostShader.BloomDownShader;
import helder.scene.render.PostShader.BloomUpShader;
import helder.scene.render.PostShader.CompositeShader;

// The post-process chain of an HDR frame (Renderer.hdr: drawn in linear
// light into an RGBA16F target): physically based bloom, then the frame
// tone mapped, graded and finished into an 8-bit target.
//
//   var post = new PostProcess(device);
//   post.bloom = 0.05;                 // the share of the light spread (0: none)
//   post.toneMap = Aces;               // or AgX, Clamp
//   post.saturation = 1.1; post.vignette = 0.25; post.grain = 0.03;
//   renderer.post = post;              // a <Scene>'s box runs it (hdr={true})
//   // or by hand, after the scene's pass into hdrColor:
//   post.run(enc, hdrColor, ldrColor, width, height, time);
//   post.add(FinishShader, finishBytes);  // a pass of its own after the grade (PostStage)
//
// Bloom has no threshold: everything spreads a little, what is bright
// (an engine, a laser, the sun: values far over 1) spreads visibly. The
// scene is filtered down a chain of RGBA16F targets each half the one
// above (levels, at most 6; the first half the frame's size, or a quarter
// with base 2: Jimenez's 13-tap filter, the first level in Karis' average)
// and back up it (a tent filter, each level added to the one above), as
// Call of Duty: Advanced Warfare and Unity's HDRP do; the composite mixes
// it in. The targets are the GPU's (as many as the levels, made at the
// first run and when the size, base or levels change, freed by dispose);
// a run records 2 * levels passes and allocates nothing. Without grain
// the dither is still: a frame drawn again is the same pixels. A program's
// own stages (add: a pixel art finish, a CRT, an outline) come after the
// composite, in order, each a pass reading the last one's image: the
// composite and all but the last stage into two RGBA8 targets of the
// run's size taken in turn, the last into the output.
class PostProcess {
	public final device:Device;
	// the light before the curve (1: as drawn)
	public var exposure = 1.0;
	// bloom's share of the frame (0 to 1: 0.04 is subtle, 0.15 dreamy; 0: no bloom passes)
	public var bloom = 0.04;
	// how far each level up spreads (its texels: 1 a tight halo, 2 wider)
	public var radius = 1.0;
	// the bloom chain's levels (1 to 6; fewer: a tighter, cheaper glow)
	public var levels = 6;
	// the first level's size: the frame's halved this many times (1 or 2;
	// 2: a quarter of the pixels to filter, the glow a little softer)
	public var base = 1;
	public var toneMap:ToneMap = Aces;
	// the grade, on the tone mapped colour: 1 as it is
	public var saturation = 1.0;
	public var contrast = 1.0;
	// added to the shadows (rgb, 0 to about 0.05) and the colour's gain (rgb)
	public var lift = new helder.gfx.shader.Vec3(0, 0, 0);
	public var gain = new helder.gfx.shader.Vec3(1, 1, 1);
	// how much darker the corners are (0 to 1)
	public var vignette = 0.0;
	// film grain's strength (0 to about 0.1); a dither below a step of 8 bits is always there
	public var grain = 0.0;
	// whether the frame's alpha is kept (the scene's coverage, where bloom
	// adds light its brightness: over a ui behind it, premultiplied); false: opaque
	public var transparent = true;

	static inline var MAX_LEVELS = 6;

	final down:Pipeline;
	final up:Pipeline;
	final composite:Pipeline;
	final triangle:Buffer;
	final linear:Sampler;
	final nearest:Sampler;
	// a program's own stages, after the composite (add)
	final stages:Array<PostStage> = [];
	// (the targets between them, made for a size)
	final between:Array<Texture> = [];
	final betweenPasses:Array<PassDesc> = [];
	var betweenW = 0;
	var betweenH = 0;
	var compositeBetween:Null<Pipeline> = null;
	final output:TextureFormat;
	final frame:Bool;
	final black:Texture;
	final bloomBytes = Bytes.alloc(BloomDownShader.uniforms[0].size);
	final compositeBytes = Bytes.alloc(CompositeShader.uniforms[0].size);
	// (the chain's targets and their passes: made for a size)
	final chain:Array<Texture> = [];
	final widths:Array<Int> = [];
	final heights:Array<Int> = [];
	final clearPasses:Array<PassDesc> = [];
	final loadPasses:Array<PassDesc> = [];
	final outPass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	var chainW = 0;
	var chainH = 0;
	var chainBase = 0;
	var chainN = 0;
	final downSlots:Array<Int>;
	final upSlots:Array<Int>;
	final compositeSlots:Array<Int>;

	// output: the format of the targets run writes (RGBA8: a <Scene>'s
	// box's); frame: run writes the frame instead (output unused)
	public function new(device:Device, output:TextureFormat = RGBA8, frame = false) {
		this.device = device;
		this.output = output;
		this.frame = frame;
		var d = BloomDownShader.pipeline({});
		d.colorFormat = RGBA16F;
		down = device.createPipeline(d);
		var u = BloomUpShader.pipeline({blend: Additive});
		u.colorFormat = RGBA16F;
		up = device.createPipeline(u);
		var c = CompositeShader.pipeline({});
		if (!frame) c.colorFormat = output;
		composite = device.createPipeline(c);
		var v = BloomDownShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
		triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		var b = Bytes.alloc(8);
		black = device.createTexture({width: 1, height: 1, format: RGBA16F, data: b});
		downSlots = [BloomDownShader.uniforms[0].binding, BloomDownShader.textures[0].binding];
		upSlots = [BloomUpShader.uniforms[0].binding, BloomUpShader.textures[0].binding];
		compositeSlots = [CompositeShader.uniforms[0].binding, CompositeShader.textures[0].binding, CompositeShader.textures[1].binding];
	}

	// the chain for a frame of width by height (its targets made again when that changes)
	function size(width:Int, height:Int, b:Int, n:Int) {
		if (width == chainW && height == chainH && b == chainBase && n <= chainN) return;
		release();
		chainW = width;
		chainH = height;
		chainBase = b;
		chainN = n;
		var w = Std.int(Math.max(1, width >> (b - 1))), h = Std.int(Math.max(1, height >> (b - 1)));
		for (k in 0...n) {
			w = Std.int(Math.max(1, w >> 1));
			h = Std.int(Math.max(1, h >> 1));
			var t = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
			chain.push(t);
			widths.push(w);
			heights.push(h);
			clearPasses.push({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: t}]});
			loadPasses.push({colors: [{load: Load, texture: t}]});
			if (w == 1 && h == 1) break;
		}
	}

	// a stage of the program's own after those before it (PostStage: its
	// shader's first texture the image so far, its first block bytes)
	public function add<V, P>(shader:helder.gfx.shader.Shader<V, P>, ?bytes:Bytes):PostStage {
		var s = new PostStage(shader, bytes);
		stages.push(s);
		return s;
	}

	public function remove(stage:PostStage)
		stages.remove(stage);

	// the frame: source (the scene's RGBA16F, width by height) into target
	// (the output format's render target of that size, or with stages any
	// size; null: the frame, a PostProcess made for it); time: seconds, the
	// grain's
	public function run(enc:Encoder, source:Texture, target:Null<Texture>, width:Int, height:Int, time = 0.0) {
		var n = bloom > 0 ? Std.int(Math.max(1, Math.min(levels, MAX_LEVELS))) : 0;
		var b = base >= 2 ? 2 : 1;
		if (n > 0) size(width, height, b, n);
		if (n > chain.length) n = chain.length;
		// (down the chain: each level from the one above, the first from the scene)
		for (k in 0...n) {
			var from = k == 0 ? source : chain[k - 1];
			var fw = k == 0 ? width : widths[k - 1], fh = k == 0 ? height : heights[k - 1];
			enc.beginPass(clearPasses[k]);
			enc.setPipeline(down);
			// (a quarter's first level: the 13 taps twice as far apart, over its 4 x 4 texels)
			var spread = k == 0 ? b : 1;
			bloomParams(spread / fw, spread / fh, 0, k == 0 ? 1 : 0);
			enc.setUniforms(downSlots[0], bloomBytes);
			enc.setTexture(downSlots[1], from, linear);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			enc.endPass();
		}
		// (back up: each level's tent filtered into the one above, added)
		var k = n - 1;
		while (k > 0) {
			enc.beginPass(loadPasses[k - 1]);
			enc.setPipeline(up);
			bloomParams(1 / widths[k], 1 / heights[k], radius, 0);
			enc.setUniforms(upSlots[0], bloomBytes);
			enc.setTexture(upSlots[1], chain[k], linear);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			enc.endPass();
			k--;
		}
		var count = 0;
		for (s in stages)
			if (s.enabled) count++;
		if (count > 0) targets(width, height);
		var into = count > 0 ? betweenPasses[0] : outPass;
		outPass.colors[0].texture = target;
		enc.beginPass(into);
		if (count > 0 && compositeBetween == null) {
			var c = CompositeShader.pipeline({});
			c.colorFormat = RGBA8;
			compositeBetween = device.createPipeline(c);
		}
		enc.setPipeline(count > 0 ? compositeBetween : composite);
		// (the first level holds the n levels' light added: lift.w, 1 / n, scales it back)
		CompositeShader.params.p.write({
			exposure: new Vec4(exposure, n > 0 ? Math.min(1, bloom) : 0, (cast toneMap : Int), grain > 0 ? time % 1000 : 0),
			grade: new Vec4(saturation, contrast, vignette, grain),
			lift: new Vec4(lift.x, lift.y, lift.z, n > 0 ? 1 / n : 0),
			gain: new Vec4(gain.x, gain.y, gain.z, 0),
			size: new Vec4(width, height, width / Math.max(1, height), transparent ? 1 : 0)
		}, compositeBytes);
		enc.setUniforms(compositeSlots[0], compositeBytes);
		enc.setTexture(compositeSlots[1], source, linear);
		enc.setTexture(compositeSlots[2], n > 0 ? chain[0] : black, linear);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		enc.endPass();
		// (the stages: each from the last target into the next, the last into the output)
		var from = 0;
		for (s in stages) {
			if (!s.enabled) continue;
			var last = --count == 0;
			if (last) enc.beginPass(outPass) else enc.beginPass(betweenPasses[1 - from]);
			enc.setPipeline(last ? stageLast(s) : stageBetween(s));
			if (s.block >= 0 && s.bytes != null) enc.setUniforms(s.block, s.bytes);
			enc.setTexture(s.source, between[from], s.filter == Nearest ? nearest : linear);
			if (s.bind != null) s.bind(enc);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			enc.endPass();
			from = 1 - from;
		}
		outPass.colors[0].texture = null;
	}

	function stageBetween(s:PostStage):Pipeline {
		if (s.middle == null) {
			s.desc.colorFormat = RGBA8;
			s.middle = device.createPipeline(s.desc);
		}
		return s.middle;
	}

	function stageLast(s:PostStage):Pipeline {
		if (s.last == null) {
			s.desc.colorFormat = frame ? null : output;
			s.last = device.createPipeline(s.desc);
		}
		return s.last;
	}

	// the two targets between the composite and the stages, of the run's size
	function targets(width:Int, height:Int) {
		if (width == betweenW && height == betweenH) return;
		releaseBetween();
		betweenW = width;
		betweenH = height;
		for (_ in 0...2) {
			var t = device.createTexture({width: width, height: height, renderTarget: true});
			between.push(t);
			betweenPasses.push({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: t}]});
		}
	}

	function releaseBetween() {
		for (t in between)
			device.destroyTexture(t);
		between.resize(0);
		betweenPasses.resize(0);
		betweenW = betweenH = 0;
	}

	inline function bloomParams(tx:Float, ty:Float, r:Float, first:Float)
		BloomDownShader.params.p.write({texel: new Vec4(tx, ty, r, first)}, bloomBytes);

	function release() {
		for (t in chain)
			device.destroyTexture(t);
		chain.resize(0);
		widths.resize(0);
		heights.resize(0);
		clearPasses.resize(0);
		loadPasses.resize(0);
		chainW = chainH = chainBase = chainN = 0;
	}

	public function dispose() {
		release();
		releaseBetween();
		device.destroyBuffer(triangle);
		device.destroyTexture(black);
	}
}

// the curve from linear light to the display
enum abstract ToneMap(Int) to Int {
	// Sobotka's AgX: hues kept, highlights to white
	var AgX;
	// ACES filmic, Narkowicz's fit: the 8-bit path's (aces), so a
	// scene tuned there keeps its look
	var Aces;
	// none: clipped at 1
	var Clamp;
}
