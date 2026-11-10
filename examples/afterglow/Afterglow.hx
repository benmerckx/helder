// title: Afterglow
// summary: A calm puzzle in overgrown ruins over still water: a tiny moth whose light wakes glyphs that move the stone, leading a larva home; a painted 2.5D diorama in helder.scene's HDR renderer, multisampled at the screen's own size and finished as a painting
// tags: 3d, shaders, post-processing, game
// demo: canvas 360x640
import BeamShader;
import FarShader;
import FinishShader;
import GlyphShader;
import MothShader;
import PaintShader;
import PaintShader.magenta;
import Puzzle;
import Ruins;
import Sdf;
import WaterShader;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;
import helder.scene.*;
import helder.scene.render.*;

// The frame: the ruins (Ruins, PaintShader) drawn upside down into a
// small target for the water's mirror, then into the renderer's HDR
// target (its BeforeOpaque and AfterOpaque injection points: the ruins
// and the screen's pieces, each posed, then the water, the shafts of
// light, the glyphs, the moth's aura, the larva, the moth and the motes),
// multisampled, at the screen's own size (or DETAIL of it), bloomed and
// tone mapped by helder's PostProcess, and finished as a painting by the
// chain's last stage (FinishShader), measured in points.
// The play is Game's: drag or tap to lead the moth.
//
//   bun run helder run examples/afterglow
//   bun run helder run --headless examples/afterglow --size 1080x1920 --snap out.png --at 4
class Afterglow {
	static inline var MAX_PIECES = 4;
	static inline var DENSITY = 0.04;
	static final VIOLET = new Vec4(0.62, 0.3, 1.0, 0);

	final device:Device;
	final renderer:Renderer;
	final post:PostProcess;
	final world = new World("afterglow");
	final eye:Node;
	final camera:Camera;
	public final ruins = new Ruins();
	public final game:Game;

	// of the screen's pixels each way what is drawn: 1 all; less only where
	// a device is too slow (-- --detail 0.7); and never more than BUDGET
	// pixels (a 5K screen's are drawn at two thirds; the finish is always the screen's)
	public static var DETAIL = 1.0;
	static inline var BUDGET = 6.6e6;
	// pixels a point (the window's scale): the finish is measured in points
	public var points = 1.0;
	// the characters alone, in their poses at a few sizes (-- --sheet)
	public var sheet = false;
	final sheetBytes:Array<Bytes> = [];

	final paint:Pipeline;
	final mirrored:Pipeline;
	final mothMirrored:Pipeline;
	final water:Pipeline;
	final aura:Pipeline;
	final moth:Pipeline;
	final motes:Pipeline;
	final beams:Pipeline;
	final glyphs:Pipeline;
	final far:Pipeline;
	final farMirrored:Pipeline;
	final farVertices:Buffer;
	final farCount:Int;

	final ruinsVertices:Buffer;
	final ruinsIndices:Buffer;
	var wide = false;
	final waterVertices:Buffer;
	final quad:Buffer;
	final moteVertices:Buffer;
	final moteCount:Int;
	final beamVertices:Buffer;
	final beamCount:Int;
	// each screen's stone and pieces, made when it is first shown
	final screenVertices:Array<Null<Buffer>> = [for (_ in Screens.all) null];
	final screenIndices:Array<Null<Buffer>> = [for (_ in Screens.all) null];
	var glyphVertices:Null<Buffer> = null;
	var glyphCount = 0;
	var shown = -1;
	final linear:Sampler;

	final paintBytes = Bytes.alloc(PaintShader.uniforms[0].size);
	final mirrorBytes = Bytes.alloc(PaintShader.uniforms[0].size);
	final pieceBytes = [for (_ in 0...MAX_PIECES) Bytes.alloc(PaintShader.uniforms[0].size)];
	final pieceMirror = [for (_ in 0...MAX_PIECES) Bytes.alloc(PaintShader.uniforms[0].size)];
	final waterBytes = Bytes.alloc(WaterShader.uniforms[0].size);
	final auraBytes = Bytes.alloc(MothShader.uniforms[0].size);
	final mothBytes = Bytes.alloc(MothShader.uniforms[0].size);
	final auraMirror = Bytes.alloc(MothShader.uniforms[0].size);
	final mothMirror = Bytes.alloc(MothShader.uniforms[0].size);
	final larvaBytes = Bytes.alloc(MothShader.uniforms[0].size);
	final larvaMirror = Bytes.alloc(MothShader.uniforms[0].size);
	final glyphBytes = Bytes.alloc(GlyphShader.uniforms[0].size);
	final finishBytes = Bytes.alloc(FinishShader.uniforms[0].size);

	// (the shaders' blocks, written each frame from these)
	final paintView:PaintView = {
		viewProj: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), moth: new Vec4(0, 0, 0, 0), aura: new Vec4(0, 0, 0, 0), pose: new Vec4(0, 0, 0, 0),
		pivot: new Vec4(0, 0, 1, 0), flags: new Vec4(0, 0, 0, 0), glowAt: [for (_ in 0...4) new Vec4(0, 0, 0, 0)],
		glowColor: [for (_ in 0...4) new Vec4(0, 0, 0, 0)]
	};
	final waterView:WaterView = {viewProj: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0)};
	final mothView:MothView = {
		viewProj: Mat4.identity(), right: new Vec4(0, 0, 0, 0), up: new Vec4(0, 0, 0, 0), moth: new Vec4(0, 0, 0, 0), color: new Vec4(0, 0, 0, 0)
	};
	final glyphView:GlyphView = {viewProj: Mat4.identity(), moth: new Vec4(0, 0, 0, 0), state: [for (_ in 0...8) new Vec4(0, 0, 0, 0)]};
	// (bands of tone, how far edges wander, the indigo's share, grain; the mist faded into)
	final finishView:FinishView = {size: new Vec4(0, 0, 0, 0), look: new Vec4(18, 0.45, 0.25, 0.09), fade: new Vec4(0.03, 0.05, 0.09, 0)};
	final mirrorPass:PassDesc = {colors: [{load: Clear, clear: new Color(0.02, 0.03, 0.06)}], depth: {load: Clear}};
	final extra:Array<Glow> = [];
	var width = 0;
	var height = 0;
	var color:Null<Texture> = null;
	var resolved:Null<Texture> = null;
	var depth:Null<Texture> = null;
	var mirror:Null<Texture> = null;
	var mirrorDepth:Null<Texture> = null;
	var time = 0.0;
	var pixel = 0.0;
	var aspect = 0.5625;

	public function new(device:Device) {
		this.device = device;
		renderer = new Renderer(device, true, 4, true);
		renderer.clearColor = new Color(0.02, 0.03, 0.06);
		post = new PostProcess(device, RGBA8, true);
		post.bloom = 0.17;
		post.radius = 1.4;
		post.toneMap = Aces;
		post.saturation = 1.15;
		post.contrast = 1.08;
		post.transparent = false;
		var finish = post.add(FinishShader, finishBytes);
		var grain = device.createTexture({width: 256, height: 256, data: noise()});
		var tiled = device.createSampler({filter: Linear, wrap: Repeat});
		finish.bind = enc -> enc.setTexture(FinishShader.textures[1].binding, grain, tiled);
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(1, 0.1, 200));
		game = new Game(still(aspect));

		paint = renderer.createPipeline(PaintShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		// (the mirror's targets are single-sampled: the water blurs it)
		mirrored = device.createPipeline(single(PaintShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true})));
		mothMirrored = device.createPipeline(single(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false})));
		water = renderer.createPipeline(WaterShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		aura = renderer.createPipeline(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		moth = renderer.createPipeline(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		motes = renderer.createPipeline(MoteShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		beams = renderer.createPipeline(BeamShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		glyphs = renderer.createPipeline(GlyphShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));

		far = renderer.createPipeline(FarShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		farMirrored = device.createPipeline(single(FarShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false})));
		var cards:Array<FarVertex> = [];
		for (c in ruins.planes)
			for (q in [[-1, 0], [1, 0], [1, 1], [-1, 0], [1, 1], [-1, 1]])
				cards.push({pos: new Vec3(q[0] * c[1], -1 + q[1] * c[2], c[0]), plane: new Vec4(c[3], c[4], c[5], c[6])});
		var fb = FarShader.vertexBytes(cards);
		farVertices = device.createBuffer({size: fb.length, usage: Vertex, data: fb});
		farCount = cards.length;

		var m = ruins.mesh;
		var vb = m.vertexBytes(), ib = m.indexBytes();
		ruinsVertices = device.createBuffer({size: vb.length, usage: Vertex, data: vb});
		ruinsIndices = device.createBuffer({size: ib.length, usage: Index, data: ib});
		var w = WaterShader.vertexBytes([
			for (p in [[-160, 12], [160, 12], [160, -85], [-160, 12], [160, -85], [-160, -85]]) {pos: new Vec3(p[0], 0, p[1])}
		]);
		waterVertices = device.createBuffer({size: w.length, usage: Vertex, data: w});
		var corners = [[-1, -1], [1, -1], [1, 1], [-1, -1], [1, 1], [-1, 1]];
		var q = MothShader.vertexBytes([for (c in corners) {corner: new Vec2(c[0], c[1])}]);
		quad = device.createBuffer({size: q.length, usage: Vertex, data: q});
		var seed = 99;
		function rand():Float {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return seed / 0x7fffffff;
		}
		var drift:Array<MoteVertex> = [];
		for (k in 0...110) {
			var at = new Vec4(-6 + rand() * 14, 0.4 + rand() * 9, -0.5 - rand() * 14, rand());
			for (c in corners)
				drift.push(({corner: new Vec2(c[0], c[1]), seed: at} : MoteVertex));
		}
		var shafts:Array<BeamVertex> = [];
		for (b in ruins.beams)
			for (c in corners)
				shafts.push(({corner: new Vec2(c[0], c[1]), at: b.at, shape: b.shape} : BeamVertex));
		var bb = BeamShader.vertexBytes(shafts);
		beamVertices = device.createBuffer({size: bb.length, usage: Vertex, data: bb});
		beamCount = shafts.length;
		var mb = MoteShader.vertexBytes(drift);
		moteVertices = device.createBuffer({size: mb.length, usage: Vertex, data: mb});
		moteCount = drift.length;
		linear = device.createSampler({filter: Linear, wrap: Clamp});

		renderer.inject(BeforeOpaque, (enc, frame) -> {
			if (sheet) return;
			enc.setPipeline(paint);
			ruinsDraw(enc, false);
		});
		renderer.inject(AfterOpaque, (enc, frame) -> {
			if (sheet) {
				enc.setVertexBuffer(0, quad);
				enc.setPipeline(aura);
				for (b in sheetBytes) {
					enc.setUniforms(MothShader.uniforms[0].binding, b);
					enc.draw(6);
				}
				return;
			}
			enc.setPipeline(water);
			enc.setUniforms(WaterShader.uniforms[0].binding, waterBytes);
			enc.setTexture(WaterShader.textures[0].binding, mirror, linear);
			enc.setVertexBuffer(0, waterVertices);
			enc.draw(6);
			farDraw(enc, far, paintBytes);
			enc.setPipeline(beams);
			enc.setUniforms(BeamShader.uniforms[0].binding, mothBytes);
			enc.setVertexBuffer(0, beamVertices);
			enc.draw(beamCount);
			if (glyphCount > 0) {
				enc.setPipeline(glyphs);
				enc.setUniforms(GlyphShader.uniforms[0].binding, glyphBytes);
				enc.setVertexBuffer(0, glyphVertices);
				enc.draw(glyphCount);
			}
			creatures(enc, aura, auraBytes, larvaBytes, mothBytes);
			enc.setPipeline(motes);
			enc.setUniforms(MoteShader.uniforms[0].binding, mothBytes);
			enc.setVertexBuffer(0, moteVertices);
			enc.draw(moteCount);
		});
	}

	function farDraw(enc:Encoder, pipeline:Pipeline, bytes:Bytes) {
		enc.setPipeline(pipeline);
		enc.setUniforms(FarShader.uniforms[0].binding, bytes);
		enc.setVertexBuffer(0, farVertices);
		enc.draw(farCount);
	}

	// the finish's noise, 256 x 256, tiling: r, g: two smooth noises (cells
	// of 16 texels), b: a cloudier one (32, 16 and 8), a: a fine one (2 and 1)
	static function noise():Bytes {
		var b = Bytes.alloc(256 * 256 * 4);
		function value(x:Float, y:Float, cell:Int, seed:Float):Float {
			var n = Std.int(256 / cell), fx = x / cell, fy = y / cell;
			var i = Math.floor(fx), j = Math.floor(fy), u = fx - i, v = fy - j;
			u = u * u * (3 - 2 * u);
			v = v * v * (3 - 2 * v);
			inline function h(a:Int, c:Int)
				return hash3(a % n, c % n, seed);
			var top = h(i, j) + (h(i + 1, j) - h(i, j)) * u, bottom = h(i, j + 1) + (h(i + 1, j + 1) - h(i, j + 1)) * u;
			return top + (bottom - top) * v;
		}
		for (y in 0...256)
			for (x in 0...256) {
				var o = (y * 256 + x) * 4;
				b.set(o, Std.int(value(x, y, 16, 1.7) * 255));
				b.set(o + 1, Std.int(value(x, y, 16, 5.3) * 255));
				b.set(o + 2, Std.int((value(x, y, 32, 9.1) * 0.5 + value(x, y, 16, 3.9) * 0.3 + value(x, y, 8, 7.7) * 0.2) * 255));
				b.set(o + 3, Std.int((value(x, y, 2, 2.3) * 0.5 + value(x, y, 1, 4.1) * 0.5) * 255));
			}
		return b;
	}

	static function single(d:PipelineDesc):PipelineDesc {
		d.colorFormat = RGBA16F;
		d.depthFormat = Depth32F;
		return d;
	}

	function creatures(enc:Encoder, pipeline:Pipeline, aura:Bytes, larva:Bytes, moth:Bytes) {
		enc.setVertexBuffer(0, quad);
		enc.setPipeline(pipeline);
		enc.setUniforms(MothShader.uniforms[0].binding, aura);
		enc.draw(6);
		enc.setUniforms(MothShader.uniforms[0].binding, larva);
		enc.draw(6);
		enc.setUniforms(MothShader.uniforms[0].binding, moth);
		enc.draw(6);
	}

	// the ruins and the screen's stone, then each piece posed; the far
	// planes and the roots only in the frame (not the mirror)
	function ruinsDraw(enc:Encoder, mirror:Bool) {
		var built = ruins.screen(game.index);
		enc.setUniforms(PaintShader.uniforms[0].binding, mirror ? mirrorBytes : paintBytes);
		enc.setVertexBuffer(0, ruinsVertices);
		enc.setIndexBuffer(ruinsIndices, UInt32);
		// (nearest first: the roots, the screen's stone, then what is behind them)
		if (!mirror) range(enc, wide ? ruins.wide : ruins.tall);
		enc.setVertexBuffer(0, screenVertices[game.index]);
		enc.setIndexBuffer(screenIndices[game.index], UInt32);
		range(enc, built.stone);
		for (k in 0...built.pieces.length) {
			enc.setUniforms(PaintShader.uniforms[0].binding, mirror ? pieceMirror[k] : pieceBytes[k]);
			range(enc, built.pieces[k]);
		}
		enc.setUniforms(PaintShader.uniforms[0].binding, mirror ? mirrorBytes : paintBytes);
		enc.setVertexBuffer(0, ruinsVertices);
		enc.setIndexBuffer(ruinsIndices, UInt32);
		range(enc, ruins.back);
	}

	inline function range(enc:Encoder, r:Range)
		if (r.count > 0) enc.drawIndexed(r.count, 1, r.first);

	// the targets for a screen of w by h
	function resize(w:Int, h:Int) {
		if (w == width && h == height) return;
		for (t in [color, resolved, depth, mirror, mirrorDepth])
			if (t != null) device.destroyTexture(t);
		width = w;
		height = h;
		var sw = smallWidth(), sh = smallHeight();
		color = device.createTexture({width: sw, height: sh, format: RGBA16F, renderTarget: true, samples: 4});
		resolved = device.createTexture({width: sw, height: sh, format: RGBA16F, renderTarget: true});
		depth = device.createTexture({width: sw, height: sh, format: Depth32F, renderTarget: true, samples: 4});
		// (the mirror at a third: the water blurs it anyway)
		mirror = device.createTexture({width: mirrorWidth(), height: mirrorHeight(), format: RGBA16F, renderTarget: true});
		mirrorDepth = device.createTexture({width: mirrorWidth(), height: mirrorHeight(), format: Depth32F, renderTarget: true});
		// (the bloom as wide on any screen: from a quarter on a large one)
		post.base = sh >= 1300 ? 2 : 1;
	}

	inline function detail():Float
		return Math.min(DETAIL, Math.sqrt(BUDGET / Math.max(1, width * height)));

	inline function smallWidth()
		return Std.int(Math.ceil(width * detail()));

	inline function smallHeight()
		return Std.int(Math.ceil(height * detail()));

	inline function mirrorWidth()
		return Std.int(Math.max(1, smallWidth() / 3));

	inline function mirrorHeight()
		return Std.int(Math.max(1, smallHeight() / 3));

	// where the camera stands: what is played with (3.3 units either side
	// on the stage's plane, 3.9 up and down) always in the frame, so a
	// narrow phone sees more above and below it, a wide window more beside
	// it; the stage low in a tall frame; a slow drift
	// (play/aim.mjs has the same numbers: the scripts' taps)
	function frame(aspect:Float) {
		var half = Math.max(3.9, 3.3 / aspect), wide = clamp((aspect - 0.5625) / (1.7778 - 0.5625), 0, 1);
		var bottom = -0.9 - (half - 3.9) * 0.37;
		var to = new Vec3(-0.05 + 0.35 * wide, bottom + half, -2.3);
		var from = stand(aspect);
		camera.fovY = 2 * Math.atan(half / length(to - from));
		eye.position = from + new Vec3(Math.sin(time * 0.11) * 0.3, Math.sin(time * 0.083 + 1) * 0.12, Math.sin(time * 0.07) * 0.3);
		eye.lookAt(to + new Vec3(Math.sin(time * 0.11) * 0.12, 0, 0));
	}

	static function stand(aspect:Float):Vec3 {
		var half = Math.max(3.9, 3.3 / aspect), wide = clamp((aspect - 0.5625) / (1.7778 - 0.5625), 0, 1);
		var y = -0.9 - (half - 3.9) * 0.37 + half;
		return new Vec3(0.15 + 0.35 * wide, 2.4 + (y - 3) * 0.2, 4.2 + half * 0.6);
	}

	// where the eye is without its drift: what the play measures by
	function still(aspect:Float):Vec {
		var e = stand(aspect);
		return {x: e.x, y: e.y, z: e.z};
	}

	// a point of the window (pixels from its top left) on the moth's plane
	public function aim(px:Float, py:Float):Vec {
		var m = camera.view();
		var right = new Vec3(m.c0.x, m.c1.x, m.c2.x), up = new Vec3(m.c0.y, m.c1.y, m.c2.y), back = new Vec3(m.c0.z, m.c1.z, m.c2.z);
		var h = Math.tan(camera.fovY / 2), nx = px / Math.max(width, 1) * 2 - 1, ny = 1 - py / Math.max(height, 1) * 2;
		var dir = right * (nx * h * aspect) + up * (ny * h) - back;
		var from = camera.eye();
		var t = (Puzzle.FLY - from.z) / dir.z;
		return {x: from.x + dir.x * t, y: from.y + dir.y * t, z: Puzzle.FLY};
	}

	// the screen's glyphs and the home's cocoon: a quad each
	function glyphQuads() {
		if (glyphVertices != null) device.destroyBuffer(glyphVertices);
		var s = Screens.all[game.index], out:Array<GlyphVertex> = [];
		var corners = [[-1, -1], [1, -1], [1, 1], [-1, -1], [1, 1], [-1, 1]];
		function add(x:Float, y:Float, z:Float, size:Float, kind:Int, entry:Int)
			for (c in corners)
				out.push(({corner: new Vec2(c[0], c[1]), at: new Vec4(x, y, z + 0.09, size), kind: new Vec4(kind, entry, 0, 0)} : GlyphVertex));
		for (k in 0...s.glyphs.length) {
			var g = s.glyphs[k];
			add(g.at[0], g.at[1], g.at[2], g.eye == true ? 0.34 : 0.42, g.eye == true ? 1 : 0, k);
		}
		var h = s.home, size = 0.62;
		add(h[0], h[1] + 0.95 * size - 0.05, h[2], size, 2, 7);
		var b = GlyphShader.vertexBytes(out);
		glyphVertices = device.createBuffer({size: b.length, usage: Vertex, data: b});
		glyphCount = out.length;
	}

	public function draw(enc:Encoder, t:Float) {
		time = t;
		resize(device.width, device.height);
		var sw = smallWidth(), sh = smallHeight();
		aspect = sw / sh;
		wide = aspect > 1;
		frame(aspect);
		game.eye = still(aspect);
		game.update(t);
		if (shown != game.index) {
			shown = game.index;
			glyphQuads();
			if (screenVertices[shown] == null) {
				var m = ruins.screen(shown).mesh, vb = m.vertexBytes(), ib = m.indexBytes();
				screenVertices[shown] = device.createBuffer({size: vb.length, usage: Vertex, data: vb});
				screenIndices[shown] = device.createBuffer({size: ib.length, usage: Index, data: ib});
			}
		}
		var puzzle = game.puzzle, fly = game.moth, larva = puzzle.larva;
		var viewProj = camera.viewProjection(aspect);
		var from = camera.eye();
		var mothAt = new Vec3(fly.x, fly.y, fly.z);

		extra.resize(0);
		for (p in puzzle.pieces)
			if (p.lantern != null && p.light > 0) {
				var l = p.lantern;
				extra.push({pos: new Vec3(l[0] + p.x, l[1] + p.y, l[2]), radius: 4.0, color: magenta(), power: 3.2 * p.light});
			}
		var h = Screens.all[game.index].home;
		extra.push({pos: new Vec3(h[0], h[1] + 0.5, h[2] + 0.5), radius: 2.2, color: magenta(), power: 0.15 + larva.home * 3});
		for (k in 0...4) {
			var l = k < extra.length ? extra[k] : null;
			paintView.glowAt[k] = l == null ? new Vec4(0, 0, 0, 0) : new Vec4(l.pos.x, l.pos.y, l.pos.z, l.radius);
			paintView.glowColor[k] = l == null ? new Vec4(0, 0, 0, 0) : new Vec4(l.color.x, l.color.y, l.color.z, l.power);
		}

		// (a pixel's size a unit away: the far planes' soft edge)
		pixel = 2 * Math.tan(camera.fovY / 2) / sh;
		var v = paintView;
		v.viewProj = viewProj;
		v.eye = new Vec4(from.x, from.y, from.z, t);
		v.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 2.8);
		v.aura = VIOLET * 2.4;
		v.pose = new Vec4(0, 0, 0, 0);
		v.pivot = new Vec4(0, 0, 1, 0);
		v.flags = new Vec4(0, 0, DENSITY, pixel);
		PaintShader.params.view.write(v, paintBytes);
		var mirrorProj = viewProj * Mat4.scaling(1, -1, 1);
		pieces(viewProj, mirrorProj, from, t);
		v.viewProj = mirrorProj;
		v.eye = new Vec4(from.x, -from.y, from.z, t);
		v.pose = new Vec4(0, 0, 0, 0);
		v.pivot = new Vec4(0, 0, 1, 0);
		v.flags = new Vec4(1, 0, DENSITY, pixel * 3);
		PaintShader.params.view.write(v, mirrorBytes);
		waterView.viewProj = viewProj;
		waterView.eye = new Vec4(from.x, from.y, from.z, t);
		waterView.size = new Vec4(sw, sh, DENSITY, 0);
		WaterShader.params.view.write(waterView, waterBytes);

		var m = camera.view();
		var w = mothView;
		var right = new Vec4(m.c0.x, m.c1.x, m.c2.x, 1.1), up = new Vec4(m.c0.y, m.c1.y, m.c2.y, t);
		w.up = up;
		w.right = right;
		w.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 0);
		w.color = VIOLET * 0.6;
		both(w, viewProj, mirrorProj, auraBytes, auraMirror);
		// (its wings: still when standing, beating in flight, from folded to raised high)
		var wings = -fly.fly * (0.95 + 0.9 * Math.sin(fly.phase));
		w.right = new Vec4(right.x, right.y, right.z, Ruins.MOTH);
		w.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 1);
		w.color = new Vec4(fly.fly, wings, fly.tilt * fly.facing, fly.facing);
		both(w, viewProj, mirrorProj, mothBytes, mothMirror);
		w.right = new Vec4(right.x, right.y, right.z, Ruins.LARVA);
		w.moth = new Vec4(larva.x, larva.y + Ruins.LARVA * 0.8 + 0.02, larva.z, 2);
		w.color = new Vec4(larva.out, larva.phase, larva.home, larva.facing);
		both(w, viewProj, mirrorProj, larvaBytes, larvaMirror);

		var g = glyphView;
		g.viewProj = viewProj;
		g.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, t);
		for (k in 0...puzzle.glyphs.length) {
			var s = puzzle.glyphs[k];
			g.state[k] = new Vec4(s.charge, s.lit ? 1 : 0, s.near, s.armed ? 1 : 0);
		}
		var near = Math.max(0, 1 - Math.abs(larva.x - h[0]) / 2.5) * (Math.abs(larva.y - h[1]) < 0.1 ? 1 : 0);
		g.state[7] = new Vec4(near, larva.home, 0, 0);
		GlyphShader.params.view.write(g, glyphBytes);

		// (the mirror: the ruins drawn upside down about the water)
		mirrorPass.colors[0].texture = mirror;
		mirrorPass.depth.texture = mirrorDepth;
		enc.beginPass(mirrorPass);
		if (!sheet) {
			enc.setPipeline(mirrored);
			ruinsDraw(enc, true);
			farDraw(enc, farMirrored, mirrorBytes);
			creatures(enc, mothMirrored, auraMirror, larvaMirror, mothMirror);
		}
		enc.endPass();
		if (sheet) poses(viewProj, right, up, t);

		renderer.drawInto(enc, world, camera, color, depth, sw, sh, resolved);
		finishView.size = new Vec4(width, height, points, t);
		finishView.fade = new Vec4(0.03, 0.05, 0.09, game.fade * game.fade * (3 - 2 * game.fade));
		FinishShader.params.view.write(finishView, finishBytes);
		post.run(enc, resolved, null, sw, sh, t);
	}

	// the characters' sheet: the moth standing (its aura about it), its
	// wings up and down in flight, facing left; the larva asleep, waking and
	// crawling; then both at the size they are played at and smaller
	function poses(viewProj:Mat4, right:Vec4, up:Vec4, t:Float) {
		// (x, y, half size, kind, then MothView's color)
		var v = VIOLET * 0.6, m = Ruins.MOTH, l = Ruins.LARVA;
		var list:Array<Array<Float>> = [
			[-4.6, 4.7, 1.9, 0, v.x, v.y, v.z, 0], [-4.6, 4.7, 1.3, 1, 0, 0, 0, 1], [-1.4, 4.7, 1.3, 1, 1, -1.8, 0.2, 1], [1.7, 4.7, 1.3, 1, 1, -0.1, -0.15, 1],
			[4.9, 4.7, 1.3, 1, 0, 0, 0, -1], [-5.0, 1.9, 1.0, 2, 0, 0, 0, 1], [-2.6, 1.9, 1.0, 2, 0.55, 0, 0, 1], [0.0, 1.9, 1.0, 2, 1, 0.15, 0, 1],
			[2.6, 1.9, 1.0, 2, 1, 0.45, 0, 1], [5.2, 1.9, 1.0, 2, 1, 0.3, 0, -1]
		];
		var x = -4.9;
		for (k in [1.0, 0.6, 0.36]) {
			var low = 0.05 - (m * 0.6 - l * 0.8) * k;
			list.push([x, 0.05, m * k, 1, 0, 0, 0, 1]);
			list.push([x + 1.3 * k, low, l * k, 2, 1, 0.2, 0, 1]);
			list.push([x + 2.4 * k, low, l * k, 2, 0, 0, 0, 1]);
			list.push([x + 3.6 * k, 0.25, m * k, 1, 1, -1.2, 0.15, -1]);
			x += 4.9 * k + 0.4;
		}
		for (k in 0...list.length) {
			var e = list[k];
			if (k == sheetBytes.length) sheetBytes.push(Bytes.alloc(MothShader.uniforms[0].size));
			mothView.viewProj = viewProj;
			mothView.right = new Vec4(right.x, right.y, right.z, e[2]);
			mothView.up = up;
			mothView.moth = new Vec4(e[0], e[1], Puzzle.FLY, e[3]);
			mothView.color = new Vec4(e[4], e[5], e[6], e[7]);
			MothShader.params.view.write(mothView, sheetBytes[k]);
		}
	}

	// each piece's block: its pose, its pivot, its lantern's light and the moth's hint at it
	function pieces(viewProj:Mat4, mirrorProj:Mat4, from:Vec3, t:Float) {
		var v = paintView, list = game.puzzle.pieces;
		for (k in 0...Std.int(Math.min(list.length, MAX_PIECES))) {
			var p = list[k], pose = p.parent != null ? [p.x, p.y, 0.0] : p.shown(), pv = p.def.pivot ?? [0, 0];
			v.pose = new Vec4(pose[0], pose[1], pose[2], 0);
			v.pivot = new Vec4(pv[0], pv[1], p.lantern != null ? ember(p.light, t) : 1, p.hint);
			v.viewProj = viewProj;
			v.eye = new Vec4(from.x, from.y, from.z, t);
			v.flags = new Vec4(0, 0, DENSITY, pixel);
			PaintShader.params.view.write(v, pieceBytes[k]);
			v.viewProj = mirrorProj;
			v.eye = new Vec4(from.x, -from.y, from.z, t);
			v.flags = new Vec4(1, 0, DENSITY, pixel * 3);
			PaintShader.params.view.write(v, pieceMirror[k]);
		}
	}

	// a lantern's light: asleep, an ember breathing (something to wake); awake, full
	static function ember(light:Float, t:Float):Float
		return 0.06 + 0.05 * Math.sin(t * 1.6) + light;

	static function both(w:MothView, viewProj:Mat4, mirrorProj:Mat4, into:Bytes, mirror:Bytes) {
		w.viewProj = viewProj;
		MothShader.params.view.write(w, into);
		w.viewProj = mirrorProj;
		MothShader.params.view.write(w, mirror);
	}

	static function main() {
		// (on the web 0 x 0: the canvas fills the page, a phone's whole screen)
		var det = Sys.args().indexOf("--detail");
		if (det >= 0) DETAIL = Std.parseFloat(Sys.args()[det + 1]);
		var window = #if (hxmc.target == "wasm32-wasi") new Window("Afterglow", 0, 0) #else new Window("Afterglow", 405, 720) #end;
		var device = Device.create(window.surface);
		var t0 = Sys.time();
		var glow = new Afterglow(device);
		if (Sys.args().indexOf("--log") >= 0)
			Sys.println('afterglow: built in ${Math.round((Sys.time() - t0) * 1000)} ms, ${Std.int(glow.ruins.mesh.count / 3)} triangles, screen 1 ${Std.int(glow.ruins.screen(0).mesh.count / 3)}');
		glow.points = window.scale;
		glow.game.log = Sys.args().indexOf("--log") >= 0;
		glow.sheet = Sys.args().indexOf("--sheet") >= 0;
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var enc = device.beginFrame();
			if (enc == null) return;
			glow.draw(enc, App.frame.time - start);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			// (a screen by its number, for trying one)
			case KeyDown if (e.key >= "1".code && e.key <= "3".code): glow.game.start(e.key - "1".code);
			case PointerDown if (e.pointer.primary || e.pointer.buttons & 1 != 0):
				var at = glow.aim(e.x, e.y - lift(e.pointer));
				glow.game.press(at.x, at.y);
			case PointerMove if (e.pointer.down):
				var at = glow.aim(e.x, e.y - lift(e.pointer));
				glow.game.drag(at.x, at.y);
			case PointerUp | PointerCancel: glow.game.release();
			case _:
		});
	}

	// (a finger hides what is under it: the moth goes a little above it)
	static function lift(p:Pointer):Float
		return p.type == Touch ? 36 * p.scale : 0;
}
