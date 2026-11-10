// title: Afterglow
// summary: Look development for a point-and-click: a tiny moth in overgrown ruins over still water, lit only by what lives there; a painted 2.5D diorama in helder.scene's HDR renderer, drawn at half size and finished in dithered, painted pixels
// tags: 3d, shaders, post-processing
// demo: canvas 360x640
import BeamShader;
import FinishShader;
import MothShader;
import PaintShader;
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
// target (its BeforeOpaque and AfterOpaque injection points: the ruins,
// then the water, the shafts of light, the moth's aura, the moth and the
// motes), bloomed and tone mapped by helder's PostProcess, all of it at
// half the screen's size or so (a pixel scale: the shorter side about
// 540), and shown in 2 x 2 pixels, dithered (FinishShader).
//
//   bun run helder run examples/afterglow
//   bun run helder run --headless examples/afterglow --size 1080x1920 --snap out.png --at 4
class Afterglow {
	final device:Device;
	final renderer:Renderer;
	final post:PostProcess;
	final world = new World("afterglow");
	final eye:Node;
	final camera:Camera;
	final ruins = new Ruins();

	final paint:Pipeline;
	final mirrored:Pipeline;
	final water:Pipeline;
	final aura:Pipeline;
	final moth:Pipeline;
	final motes:Pipeline;
	final beams:Pipeline;
	final finish:Pipeline;

	final ruinsVertices:Buffer;
	final ruinsIndices:Buffer;
	var wide = false;
	final waterVertices:Buffer;
	final quad:Buffer;
	final moteVertices:Buffer;
	final moteCount:Int;
	final beamVertices:Buffer;
	final beamCount:Int;
	final triangle:Buffer;
	final lights:Texture;
	final lightData = Bytes.alloc(32 * 16);
	final nearest:Sampler;
	final linear:Sampler;

	final paintBytes = Bytes.alloc(PaintShader.uniforms[0].size);
	final mirrorBytes = Bytes.alloc(PaintShader.uniforms[0].size);
	final waterBytes = Bytes.alloc(WaterShader.uniforms[0].size);
	final auraBytes = Bytes.alloc(MothShader.uniforms[0].size);
	final mothBytes = Bytes.alloc(MothShader.uniforms[0].size);
	final auraMirror = Bytes.alloc(MothShader.uniforms[0].size);
	final mothMirror = Bytes.alloc(MothShader.uniforms[0].size);
	final finishBytes = Bytes.alloc(FinishShader.uniforms[0].size);

	// (the shaders' blocks, written each frame from these: nothing allocated)
	final paintView:PaintView = {
		viewProj: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), moth: new Vec4(0, 0, 0, 0), aura: new Vec4(0, 0, 0, 0), glyph: new Vec4(0, 0, 0, 0),
		flags: new Vec4(0, 0, 0, 0)
	};
	final waterView:WaterView = {viewProj: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0)};
	final mothView:MothView = {
		viewProj: Mat4.identity(), right: new Vec4(0, 0, 0, 0), up: new Vec4(0, 0, 0, 0), moth: new Vec4(0, 0, 0, 0), color: new Vec4(0, 0, 0, 0)
	};
	// (levels, the dither's strength, the indigo's share, grain)
	final finishView:FinishView = {size: new Vec4(0, 0, 0, 0), look: new Vec4(32, 0.9, 0.25, 0.2)};
	final mirrorPass:PassDesc = {colors: [{load: Clear, clear: new Color(0.02, 0.03, 0.06)}], depth: {load: Clear}};
	final framePass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0)}]};
	var width = 0;
	var height = 0;
	var scale = 1;
	var color:Null<Texture> = null;
	var depth:Null<Texture> = null;
	var mirror:Null<Texture> = null;
	var mirrorDepth:Null<Texture> = null;
	var small:Null<Texture> = null;
	var lightCount = 0;
	var time = 0.0;
	var mothAt = new Vec3(0, 0, 0);

	static inline var DENSITY = 0.04;

	public function new(device:Device) {
		this.device = device;
		renderer = new Renderer(device, true, 1, true);
		renderer.clearColor = new Color(0.02, 0.03, 0.06);
		post = new PostProcess(device, RGBA8);
		post.bloom = 0.17;
		post.radius = 1.4;
		post.toneMap = Aces;
		post.saturation = 1.15;
		post.contrast = 1.08;
		post.transparent = false;
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(1, 0.1, 200));

		paint = renderer.createPipeline(PaintShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		mirrored = renderer.createPipeline(PaintShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		water = renderer.createPipeline(WaterShader.pipeline({cull: Cull.None, depthCompare: Less, depthWrite: true}));
		aura = renderer.createPipeline(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		moth = renderer.createPipeline(MothShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		motes = renderer.createPipeline(MoteShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		beams = renderer.createPipeline(BeamShader.pipeline({blend: Premultiplied, cull: Cull.None, depthCompare: Less, depthWrite: false}));
		finish = device.createPipeline(FinishShader.pipeline({}));

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
		var t = FinishShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
		triangle = device.createBuffer({size: t.length, usage: Vertex, data: t});
		lights = device.createTexture({width: 2, height: 32, format: RGBA16F, data: lightData});
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		linear = device.createSampler({filter: Linear, wrap: Clamp});

		renderer.inject(BeforeOpaque, (enc, frame) -> {
			enc.setPipeline(paint);
			ruinsDraw(enc, paintBytes);
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
			enc.setPipeline(aura);
			enc.setUniforms(MothShader.uniforms[0].binding, auraBytes);
			enc.setVertexBuffer(0, quad);
			enc.draw(6);
			enc.setPipeline(moth);
			enc.setUniforms(MothShader.uniforms[0].binding, mothBytes);
			enc.draw(6);
			enc.setPipeline(motes);
			enc.setUniforms(MoteShader.uniforms[0].binding, mothBytes);
			enc.setVertexBuffer(0, moteVertices);
			enc.draw(moteCount);
		});
	}

	// (into the mirror: all but the far planes)
	function ruinsDraw(enc:Encoder, view:Bytes, mirror = false) {
		enc.setUniforms(PaintShader.uniforms[0].binding, view);
		enc.setTexture(PaintShader.textures[0].binding, lights, nearest);
		enc.setVertexBuffer(0, ruinsVertices);
		enc.setIndexBuffer(ruinsIndices, UInt32);
		enc.drawIndexed(mirror ? ruins.mirrored : ruins.common);
		if (wide) enc.drawIndexed(ruins.mesh.count - ruins.tall, 1, ruins.tall);
		else enc.drawIndexed(ruins.tall - ruins.common, 1, ruins.common);
	}

	// the targets for a screen of w by h: drawn at 1 / scale of it
	function resize(w:Int, h:Int) {
		if (w == width && h == height) return;
		for (t in [color, depth, mirror, mirrorDepth, small])
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
		small = device.createTexture({width: sw, height: sh, format: RGBA8, renderTarget: true});
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

	public function draw(enc:Encoder, t:Float) {
		time = t;
		resize(device.width, device.height);
		var sw = smallWidth(), sh = smallHeight(), aspect = sw / sh;
		wide = aspect > 1;
		frame(aspect);
		var viewProj = camera.viewProjection(aspect);
		var from = camera.eye();
		// (it stands on the ledge, facing into the room)
		var facing = 1;
		mothAt = ruins.moth;
		lightCount = ruins.lightBytes(t, lightData);
		device.writeTexture(lights, lightData);
		var violet = new Vec4(0.62, 0.3, 1.0, 0);
		var v = paintView;
		v.viewProj = viewProj;
		v.eye = new Vec4(from.x, from.y, from.z, t);
		v.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 2.8);
		v.aura = violet * 2.4;
		v.glyph = ruins.glyph;
		v.flags = new Vec4(0, lightCount, DENSITY, 0);
		PaintShader.params.view.write(v, paintBytes);
		var mirrorProj = viewProj * Mat4.scaling(1, -1, 1);
		v.viewProj = mirrorProj;
		v.eye = new Vec4(from.x, -from.y, from.z, t);
		v.flags = new Vec4(1, lightCount, DENSITY, 0);
		PaintShader.params.view.write(v, mirrorBytes);
		waterView.viewProj = viewProj;
		waterView.eye = new Vec4(from.x, from.y, from.z, t);
		waterView.size = new Vec4(sw, sh, DENSITY, 0);
		WaterShader.params.view.write(waterView, waterBytes);
		var m = camera.view();
		var w = mothView;
		w.viewProj = viewProj;
		w.right = new Vec4(m.c0.x, m.c1.x, m.c2.x, 1.1);
		w.up = new Vec4(m.c0.y, m.c1.y, m.c2.y, t);
		w.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 0);
		w.color = violet * 0.6;
		MothShader.params.view.write(w, auraBytes);
		w.viewProj = mirrorProj;
		MothShader.params.view.write(w, auraMirror);
		w.right = new Vec4(m.c0.x, m.c1.x, m.c2.x, Ruins.MOTH);
		w.moth = new Vec4(mothAt.x, mothAt.y, mothAt.z, 1);
		w.color = new Vec4(violet.x, violet.y, violet.z, facing);
		MothShader.params.view.write(w, mothMirror);
		w.viewProj = viewProj;
		MothShader.params.view.write(w, mothBytes);

		// (the mirror: the ruins drawn upside down about the water)
		mirrorPass.colors[0].texture = mirror;
		mirrorPass.depth.texture = mirrorDepth;
		enc.beginPass(mirrorPass);
		enc.setPipeline(mirrored);
		ruinsDraw(enc, mirrorBytes, true);
		enc.setVertexBuffer(0, quad);
		enc.setPipeline(aura);
		enc.setUniforms(MothShader.uniforms[0].binding, auraMirror);
		enc.draw(6);
		enc.setPipeline(moth);
		enc.setUniforms(MothShader.uniforms[0].binding, mothMirror);
		enc.draw(6);
		enc.endPass();

		renderer.drawInto(enc, world, camera, color, depth, sw, sh);
		post.run(enc, color, small, sw, sh, t);

		finishView.size = new Vec4(sw, sh, scale, t);
		FinishShader.params.view.write(finishView, finishBytes);
		enc.beginPass(framePass);
		enc.setPipeline(finish);
		enc.setUniforms(FinishShader.uniforms[0].binding, finishBytes);
		enc.setTexture(FinishShader.textures[0].binding, small, nearest);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		enc.endPass();
	}

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
			case _:
		});
	}
}
