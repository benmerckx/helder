package viewer;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.ui.Event;
import viewer.PhotoShader;

// The image shown, in ui's layout: each frame it is painted (a change: the
// viewer's version), the camera's rectangle is drawn into a texture of the
// box's size in device pixels before ui's pass (as helder.sprite's
// SpriteBox), on the neutral background, and ui shows that texture. The
// image's texture is RGBA8Srgb with every mip level (generated: a fitted
// photo is read trilinearly, its levels averaged in linear light), read
// nearest from 200% up (the pixels themselves). The pointer: a drag pans
// (let go moving, it glides), a double click is the fit and 100% in turn,
// the wheel and a pinch the viewer's (Viewer.wheel). Without a GPU (a
// story, a test) it lays out and hits, and draws nothing.
class ImageView extends helder.ui.Node {
	// the background, as sRGB (#161618) and as linear light
	public static inline var BACKGROUND = 0x161618;

	final viewer:Viewer;
	var device:Null<Device>;
	var target:Null<Texture>;
	var tw = 0;
	var th = 0;
	final retired:Array<{t:Texture, at:Int}> = [];
	var records = 0;
	var queued = -1;
	// the image's texture: what it shows (a decode and its frame)
	var texture:Null<Texture>;
	var texShown:Null<viewer.Decode.Decoded> = null;
	var texFrame = -1;
	var pipeline:Null<Pipeline>;
	var corners:Null<helder.gfx.Buffer>;
	var indices:Null<helder.gfx.Buffer>;
	var linear:Null<Sampler>;
	var nearest:Null<Sampler>;
	final uniforms = Bytes.alloc(32);
	// device pixels a point (the renderer's), for the pointer's points
	var density = 1.0;
	// (a drag: where it was, its speed; the last press, for a double click)
	var dragging = false;
	var lastX = 0.0;
	var lastY = 0.0;
	var lastT = 0.0;
	var speedX = 0.0;
	var speedY = 0.0;
	var pressT = -1.0;
	var pressX = 0.0;
	var pressY = 0.0;
	final id = -2000001;

	// (the image's rectangle as a node of its own, in points: where it is
	// for the tree, the tests and the stories)
	public final frame = new helder.ui.Node("image-rect");

	public function new(viewer:Viewer) {
		super("photo");
		this.viewer = viewer;
		frame.style.position = Absolute;
		frame.style.pointerEvents = None;
		frame.style.display = None;
		append(frame);
		onPointerDown = down;
		onPointerMove = move;
		onPointerUp = up;
		onPointerCancel = _ -> dragging = false;
		onWheel = e -> {
			viewer.wheel(e.localX * density, e.localY * density, e.deltaY * density, e.mods & helder.ui.Key.MOD_CONTROL != 0, haxe.Timer.stamp());
			e.preventDefault();
		};
	}

	override public function hasContent():Bool
		return true;

	function down(e:Event) {
		var now = haxe.Timer.stamp();
		// (a second press within 0.4 s and 6 points: a double click)
		if (pressT >= 0 && now - pressT < 0.4 && Math.abs(e.localX - pressX) < 6 && Math.abs(e.localY - pressY) < 6) {
			pressT = -1;
			viewer.toggleZoom(e.localX * density, e.localY * density);
			return;
		}
		pressT = now;
		pressX = e.localX;
		pressY = e.localY;
		dragging = true;
		viewer.camera.stop();
		lastX = e.localX;
		lastY = e.localY;
		lastT = now;
		speedX = speedY = 0;
		capture();
	}

	function move(e:Event) {
		if (!dragging) return;
		var now = haxe.Timer.stamp(), dx = e.localX - lastX, dy = e.localY - lastY, dt = Math.max(1e-3, now - lastT);
		if (dx == 0 && dy == 0) return;
		viewer.pan(dx * density, dy * density);
		// (the speed: a short running mean of the last moves)
		speedX = speedX * 0.5 + dx * density / dt * 0.5;
		speedY = speedY * 0.5 + dy * density / dt * 0.5;
		lastX = e.localX;
		lastY = e.localY;
		lastT = now;
	}

	function up(e:Event) {
		if (!dragging) return;
		dragging = false;
		// (let go still: no glide; moving: a slight one)
		if (haxe.Timer.stamp() - lastT < 0.08) viewer.camera.fling(speedX * 0.6, speedY * 0.6);
		if (ui != null) ui.requestFrame();
	}


	override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		var r = Std.downcast(canvas, helder.ui.draw.Renderer);
		if (r == null) {
			viewer.camera.setView(width, height);
			return;
		}
		density = r.scale;
		var pw = Std.int(Math.max(1, Math.round(width * r.scale))), ph = Std.int(Math.max(1, Math.round(height * r.scale)));
		if (device == null) setup(r.device);
		if (pw != tw || ph != th) {
			if (target != null) retired.push({t: target, at: records});
			target = device.createTexture({width: pw, height: ph, renderTarget: true});
			tw = pw;
			th = ph;
		}
		while (retired.length > 0 && records >= retired[0].at + 2)
			device.destroyTexture(retired.shift().t);
		viewer.camera.setView(pw, ph);
		upload();
		if (queued != r.frames) {
			queued = r.frames;
			r.beforePass(record);
		}
		r.gpuTexture(target, id, x, y, width, height);
	}

	function setup(d:Device) {
		device = d;
		pipeline = d.createPipeline(PhotoShader.pipeline());
		var vb = PhotoShader.vertexBytes([for (c in [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]) {corner: helder.gfx.shader.ShaderMath.vec2(c[0], c[1])}]);
		corners = d.createBuffer({size: vb.length, usage: Vertex, data: vb});
		var ib = Bytes.alloc(12);
		for (k in 0...6)
			ib.setUInt16(2 * k, [0, 1, 2, 0, 2, 3][k]);
		indices = d.createBuffer({size: ib.length, usage: Index, data: ib});
		linear = d.createSampler({filter: Linear, mipFilter: Linear, wrap: Clamp});
		nearest = d.createSampler({filter: Nearest, mipFilter: Linear, wrap: Clamp});
	}

	// (the shown decode's frame in the texture, its mip levels made)
	function upload() {
		var d = viewer.shown;
		if (d == null) return;
		if (d == texShown && viewer.frame == texFrame) return;
		var f = d.frames[viewer.frame];
		if (d != texShown) {
			if (texture != null) retired.push({t: texture, at: records});
			texture = device.createTexture({width: d.pixelsWidth, height: d.pixelsHeight, format: RGBA8Srgb, mipLevels: 0, data: f.rgba});
		} else
			device.writeTexture(texture, f.rgba);
		device.generateMips(texture);
		texShown = d;
		texFrame = viewer.frame;
	}

	function record(enc:Encoder) {
		records++;
		var t = target;
		if (t == null) return;
		var bg = BACKGROUND;
		var clear = new Color(((bg >> 16) & 255) / 255, ((bg >> 8) & 255) / 255, (bg & 255) / 255, 1);
		enc.beginPass({colors: [{load: Clear, clear: clear, texture: t}]});
		var d = viewer.shown;
		if (d != null && texture != null && texShown == d) {
			var c = viewer.camera, rect = c.rect();
			// (device pixels to clip space: y up)
			PhotoShader.writePhotoView({
				rect: helder.gfx.shader.ShaderMath.vec4(rect.x / tw * 2 - 1, 1 - rect.y / th * 2, (rect.x + rect.width) / tw * 2 - 1, 1 - (rect.y + rect.height) / th * 2),
				background: helder.gfx.shader.ShaderMath.vec4(lin(bg >> 16), lin(bg >> 8), lin(bg), 1)
			}, uniforms);
			enc.setPipeline(pipeline);
			enc.setUniforms(0, uniforms);
			enc.setTexture(1, texture, c.scale >= 2 ? nearest : linear);
			enc.setVertexBuffer(0, corners);
			enc.setIndexBuffer(indices, UInt16);
			enc.drawIndexed(6);
		}
		enc.endPass();
	}

	// (an sRGB byte as linear light)
	static function lin(v:Int):Float {
		var c = (v & 255) / 255;
		return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
	}

	// asks for a frame (the viewer changed); the image's rectangle placed
	public function redraw() {
		var d = viewer.shown;
		frame.style.display = d == null ? None : Flex;
		if (d != null) {
			var r = viewer.camera.rect(), k = density;
			frame.style.left = r.x / k;
			frame.style.top = r.y / k;
			frame.style.width = r.width / k;
			frame.style.height = r.height / k;
		}
		if (ui != null) ui.requestFrame();
	}
}
