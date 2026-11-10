// title: Afterglow
// summary: A calm puzzle in overgrown ruins over still water: a tiny moth whose light wakes glyphs that move the stone, leading a snail home; a painted 2.5D diorama in helder.scene's HDR renderer, drawn at half size and finished in dithered, painted pixels
// tags: 3d, shaders, post-processing, game
// demo: canvas 360x640
import BeamShader;
import FinishShader;
import GlyphShader;
import MothShader;
import PaintShader;
import PaintShader.magenta;
import Puzzle;
import Ruins;
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
// light, the glyphs, the moth's aura, the snail, the moth and the motes),
// bloomed and tone mapped by helder's PostProcess, all of it at half the
// screen's size or so (a pixel scale: the shorter side about 540), and
// shown in 2 x 2 pixels, dithered, by the chain's last stage (FinishShader).
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
	final ruins = new Ruins();
	public final game:Game;

	final paint:Pipeline;
	final mirrored:Pipeline;
	final water:Pipeline;
	final aura:Pipeline;
	final moth:Pipeline;
	final motes:Pipeline;
	final beams:Pipeline;
	final glyphs:Pipeline;

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
	final lights:Texture;
	final lightData = Bytes.alloc(32 * 16);
	final nearest:Sampler;
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
	final snailBytes = Bytes.alloc(MothShader.uniforms[0].size);
	final snailMirror = Bytes.alloc(MothShader.uniforms[0].size);
	final glyphBytes = Bytes.alloc(GlyphShader.uniforms[0].size);
	final finishBytes = Bytes.alloc(FinishShader.uniforms[0].size);

	// (the shaders' blocks, written each frame from these)
	final paintView:PaintView = {
		viewProj: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), moth: new Vec4(0, 0, 0, 0), aura: new Vec4(0, 0, 0, 0), pose: new Vec4(0, 0, 0, 0),
		pivot: new Vec4(0, 0, 1, 0), flags: new Vec4(0, 0, 0, 0)
	};
	final waterView:WaterView = {viewProj: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0)};
	final mothView:MothView = {
		viewProj: Mat4.identity(), right: new Vec4(0, 0, 0, 0), up: new Vec4(0, 0, 0, 0), moth: new Vec4(0, 0, 0, 0), color: new Vec4(0, 0, 0, 0)
	};
	final glyphView:GlyphView = {viewProj: Mat4.identity(), moth: new Vec4(0, 0, 0, 0), state: [for (_ in 0...8) new Vec4(0, 0, 0, 0)]};
	// (levels, the dither's strength, the indigo's share, grain; the mist faded into)
	final finishView:FinishView = {size: new Vec4(0, 0, 0, 0), look: new Vec4(32, 0.9, 0.25, 0.2), fade: new Vec4(0.03, 0.05, 0.09, 0)};
	final mirrorPass:PassDesc = {colors: [{load: Clear, clear: new Color(0.02, 0.03, 0.06)}], depth: {load: Clear}};
	final extra:Array<Glow> = [];
	var width = 0;
	var height = 0;
	var scale = 1;
	var color:Null<Texture> = null;
	var depth:Null<Texture> = null;
	var mirror:Null<Texture> = null;
	var mirrorDepth:Null<Texture> = null;
	var lightCount = 0;
	var time = 0.0;
	var aspect = 0.5625;

	public function new(device:Device) {
		this.device = device;
		renderer = new Renderer(device, true, 1, true);
		renderer.clearColor = new Color(0.02, 0.03, 0.06);
		post = new PostProcess(device, RGBA8, true);
		post.bloom = 0.17;
		post.radius = 1.4;
		post.toneMap = Aces;
		post.saturation = 1.15;
		post.contrast = 1.08;
		post.transparent = false;
		post.add(FinishShader, finishBytes).filter = Nearest;
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(1, 0.1, 200));
		game = new Game(still(aspect));

		paint = renderer.createPipeline(PaintShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		mirrored = renderer.createPipeline(PaintShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		water = renderer.createPipeline(WaterShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		aura = renderer.createPipeline(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		moth = renderer.createPipeline(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		motes = renderer.createPipeline(MoteShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		beams = renderer.createPipeline(BeamShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		glyphs = renderer.createPipeline(GlyphShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));

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
		lights = device.createTexture({width: 2, height: 32, format: RGBA16F, data: lightData});
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		linear = device.createSampler({filter: Linear, wrap: Clamp});

		renderer.inject(BeforeOpaque, (enc, frame) -> {
			enc.setPipeline(paint);
			ruinsDraw(enc, false);
		});
		renderer.inject(AfterOpaque, (enc, frame) -> {
			enc.setPipeline(water);
			enc.setUniforms(WaterShader.uniforms[0].binding, waterBytes);
			enc.setTexture(WaterShader.textures[0].binding, mirror, linear);
			enc.setVertexBuffer(0, waterVertices);
			enc.draw(6);
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
			creatures(enc, auraBytes, snailBytes, mothBytes);
			enc.setPipeline(motes);
			enc.setUniforms(MoteShader.uniforms[0].binding, mothBytes);
			enc.setVertexBuffer(0, moteVertices);
			enc.draw(moteCount);
		});
	}

	function creatures(enc:Encoder, aura:Bytes, snail:Bytes, moth:Bytes) {
		enc.setVertexBuffer(0, quad);
		enc.setPipeline(this.aura);
		enc.setUniforms(MothShader.uniforms[0].binding, aura);
		enc.draw(6);
		enc.setPipeline(this.moth);
		enc.setUniforms(MothShader.uniforms[0].binding, snail);
		enc.draw(6);
		enc.setUniforms(MothShader.uniforms[0].binding, moth);
		enc.draw(6);
	}

	// the ruins and the screen's stone, then each piece posed; the far
	// planes and the roots only in the frame (not the mirror)
	function ruinsDraw(enc:Encoder, mirror:Bool) {
		var built = ruins.screen(game.index);
		enc.setUniforms(PaintShader.uniforms[0].binding, mirror ? mirrorBytes : paintBytes);
		enc.setTexture(PaintShader.textures[0].binding, lights, nearest);
		enc.setVertexBuffer(0, ruinsVertices);
		enc.setIndexBuffer(ruinsIndices, UInt32);
		range(enc, ruins.back);
		if (!mirror) {
			range(enc, ruins.far);
			range(enc, wide ? ruins.wide : ruins.tall);
		}
		enc.setVertexBuffer(0, screenVertices[game.index]);
		enc.setIndexBuffer(screenIndices[game.index], UInt32);
		range(enc, built.stone);
		for (k in 0...built.pieces.length) {
			enc.setUniforms(PaintShader.uniforms[0].binding, mirror ? pieceMirror[k] : pieceBytes[k]);
			range(enc, built.pieces[k]);
		}
	}

	inline function range(enc:Encoder, r:Range)
		if (r.count > 0) enc.drawIndexed(r.count, 1, r.first);

	// the targets for a screen of w by h: drawn at 1 / scale of it
	function resize(w:Int, h:Int) {
		if (w == width && h == height) return;
		for (t in [color, depth, mirror, mirrorDepth])
			if (t != null) device.destroyTexture(t);
		width = w;
		height = h;
		scale = Std.int(Math.max(1, Math.round(Math.min(w, h) / 540)));
		var sw = smallWidth(), sh = smallHeight();
		color = device.createTexture({width: sw, height: sh, format: RGBA16F, renderTarget: true});
		depth = device.createTexture({width: sw, height: sh, format: Depth32F, renderTarget: true});
		// (the mirror at half size: the water blurs it anyway)
		mirror = device.createTexture({width: sw >> 1, height: sh >> 1, format: RGBA16F, renderTarget: true});
		mirrorDepth = device.createTexture({width: sw >> 1, height: sh >> 1, format: Depth32F, renderTarget: true});
	}

	inline function smallWidth()
		return Std.int(Math.ceil(width / scale));

	inline function smallHeight()
		return Std.int(Math.ceil(height / scale));

	// where the camera stands: a portrait screen looks up the ledge into
	// the arch, a landscape one wider and lower; a slow drift either way
	function frame(aspect:Float) {
		var f = clamp((aspect - 0.5625) / (1.7778 - 0.5625), 0, 1);
		var drift = new Vec3(Math.sin(time * 0.11) * 0.35, Math.sin(time * 0.083 + 1) * 0.15, Math.sin(time * 0.07) * 0.3);
		var from = mix(new Vec3(0.3, 2.3, 5.4), new Vec3(0.8, 2.0, 7.0), f) + drift;
		var to = mix(new Vec3(-0.6, 3.9, -8), new Vec3(0.4, 4.1, -8), f);
		camera.fovY = mix(1.12, 0.82, f);
		eye.position = from;
		eye.lookAt(to);
	}

	// where the eye is without its drift: what the play measures by
	function still(aspect:Float):Vec {
		var f = clamp((aspect - 0.5625) / (1.7778 - 0.5625), 0, 1);
		var e = mix(new Vec3(0.3, 2.3, 5.4), new Vec3(0.8, 2.0, 7.0), f);
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

	// the screen's glyphs and the home's door: a quad each
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
		var puzzle = game.puzzle, fly = game.moth, snail = puzzle.snail;
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
		extra.push({pos: new Vec3(h[0], h[1] + 0.5, h[2] + 0.5), radius: 1.8, color: WARM, power: 0.5 + snail.home * 2.5});
		lightCount = ruins.lightBytes(t, game.index, extra, lightData);
		device.writeTexture(lights, lightData);

		var v = paintView;
		v.viewProj = viewProj;
		v.eye = new Vec4(from.x, from.y, from.z, t);
		v.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 2.8);
		v.aura = VIOLET * 2.4;
		v.pose = new Vec4(0, 0, 0, 0);
		v.pivot = new Vec4(0, 0, 1, 0);
		v.flags = new Vec4(0, lightCount, DENSITY, 0);
		PaintShader.params.view.write(v, paintBytes);
		var mirrorProj = viewProj * Mat4.scaling(1, -1, 1);
		pieces(viewProj, mirrorProj, from, t);
		v.viewProj = mirrorProj;
		v.eye = new Vec4(from.x, -from.y, from.z, t);
		v.pose = new Vec4(0, 0, 0, 0);
		v.pivot = new Vec4(0, 0, 1, 0);
		v.flags = new Vec4(1, lightCount, DENSITY, 0);
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
		w.right = new Vec4(right.x, right.y, right.z, Ruins.SNAIL);
		w.moth = new Vec4(snail.x, snail.y + Ruins.SNAIL * 0.8 + 0.02, snail.z, 2);
		w.color = new Vec4(snail.out, snail.phase, snail.home, snail.facing);
		both(w, viewProj, mirrorProj, snailBytes, snailMirror);

		var g = glyphView;
		g.viewProj = viewProj;
		g.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, t);
		for (k in 0...puzzle.glyphs.length) {
			var s = puzzle.glyphs[k];
			g.state[k] = new Vec4(s.charge, s.lit ? 1 : 0, s.near, s.armed ? 1 : 0);
		}
		var near = Math.max(0, 1 - Math.abs(snail.x - h[0]) / 2.5) * (Math.abs(snail.y - h[1]) < 0.1 ? 1 : 0);
		g.state[7] = new Vec4(near, snail.home, 0, 0);
		GlyphShader.params.view.write(g, glyphBytes);

		// (the mirror: the ruins drawn upside down about the water)
		mirrorPass.colors[0].texture = mirror;
		mirrorPass.depth.texture = mirrorDepth;
		enc.beginPass(mirrorPass);
		enc.setPipeline(mirrored);
		ruinsDraw(enc, true);
		creatures(enc, auraMirror, snailMirror, mothMirror);
		enc.endPass();

		renderer.drawInto(enc, world, camera, color, depth, sw, sh);
		finishView.size = new Vec4(sw, sh, scale, t);
		finishView.fade = new Vec4(0.03, 0.05, 0.09, game.fade * game.fade * (3 - 2 * game.fade));
		FinishShader.params.view.write(finishView, finishBytes);
		post.run(enc, color, null, sw, sh, t);
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
			v.flags = new Vec4(0, lightCount, DENSITY, 0);
			PaintShader.params.view.write(v, pieceBytes[k]);
			v.viewProj = mirrorProj;
			v.eye = new Vec4(from.x, -from.y, from.z, t);
			v.flags = new Vec4(1, lightCount, DENSITY, 0);
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

	static final WARM = new Vec3(1.0, 0.55, 0.18);

	static function main() {
		var window = new Window("Afterglow", 405, 720);
		var device = Device.create(window.surface);
		var glow = new Afterglow(device);
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
