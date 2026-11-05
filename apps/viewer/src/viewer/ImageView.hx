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
	// the image's textures: tiles of at most TILE a side (a larger image's
	// past one texture's limit), each with MARGIN pixels of its neighbours
	// around it (so that filtering and the mip levels read across a seam);
	// what they show (a decode and its frame)
	public static inline var TILE = 4096;
	static inline var MARGIN = 64;
	final tiles:Array<Tile> = [];
	var texShown:Null<viewer.Decode.Decoded> = null;
	var texFrame = -1;
	var pipeline:Null<Pipeline>;
	var corners:Null<helder.gfx.Buffer>;
	var indices:Null<helder.gfx.Buffer>;
	var linear:Null<Sampler>;
	var nearest:Null<Sampler>;

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
		var f = d.frames[viewer.frame], pw = d.pixelsWidth, ph = d.pixelsHeight;
		var src = f.pixels.view();
		if (d != texShown) {
			for (t in tiles)
				retired.push({t: t.texture, at: records});
			tiles.resize(0);
			var step = TILE - 2 * MARGIN;
			var nx = pw <= TILE ? 1 : Math.ceil(pw / step), ny = ph <= TILE ? 1 : Math.ceil(ph / step);
			for (j in 0...ny)
				for (i in 0...nx) {
					var x0 = nx == 1 ? 0 : i * step, y0 = ny == 1 ? 0 : j * step;
					var x1 = nx == 1 ? pw : Std.int(Math.min(pw, x0 + step)), y1 = ny == 1 ? ph : Std.int(Math.min(ph, y0 + step));
					var tx = Std.int(Math.max(0, x0 - MARGIN)), ty = Std.int(Math.max(0, y0 - MARGIN));
					var tw = Std.int(Math.min(pw, x1 + MARGIN)) - tx, th = Std.int(Math.min(ph, y1 + MARGIN)) - ty;
					var t = new Tile(x0, y0, x1, y1, tx, ty, tw, th);
					t.texture = device.createTexture({width: tw, height: th, format: RGBA8Srgb, mipLevels: 0, data: t.pixels(src, pw)});
					tiles.push(t);
				}
		} else
			for (t in tiles)
				device.writeTexture(t.texture, t.pixels(src, pw));
		for (t in tiles)
			device.generateMips(t.texture);
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
		if (d != null && tiles.length > 0 && texShown == d) {
			var c = viewer.camera, rect = c.rect();
			// (the decoded pixels' size on the view: a JPEG decoded smaller is magnified the more)
			var kx = rect.width / d.pixelsWidth, ky = rect.height / d.pixelsHeight;
			enc.setPipeline(pipeline);
			enc.setVertexBuffer(0, corners);
			enc.setIndexBuffer(indices, UInt16);
			for (t in tiles) {
				var x0 = rect.x + t.x0 * kx, y0 = rect.y + t.y0 * ky, x1 = rect.x + t.x1 * kx, y1 = rect.y + t.y1 * ky;
				// (off the view: not drawn)
				if (x1 < 0 || y1 < 0 || x0 > tw || y0 > th) continue;
				// (device pixels to clip space: y up)
				PhotoShader.writePhotoView({
					rect: helder.gfx.shader.ShaderMath.vec4(x0 / tw * 2 - 1, 1 - y0 / th * 2, x1 / tw * 2 - 1, 1 - y1 / th * 2),
					uv: helder.gfx.shader.ShaderMath.vec4((t.x0 - t.tx) / t.tw, (t.y0 - t.ty) / t.th, (t.x1 - t.tx) / t.tw, (t.y1 - t.ty) / t.th),
					background: helder.gfx.shader.ShaderMath.vec4(lin(bg >> 16), lin(bg >> 8), lin(bg), 1)
				}, t.uniforms);
				enc.setUniforms(0, t.uniforms);
				enc.setTexture(1, t.texture, kx >= 2 ? nearest : linear);
				enc.drawIndexed(6);
			}
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

// (a tile: the decoded pixels' region it draws, [x0, x1) x [y0, y1), and
// its texture's, tx, ty, tw x th: the region and its margin)
private class Tile {
	public final x0:Int;
	public final y0:Int;
	public final x1:Int;
	public final y1:Int;
	public final tx:Int;
	public final ty:Int;
	public final tw:Int;
	public final th:Int;
	public var texture:Null<Texture>;
	public final uniforms = Bytes.alloc(48);

	public function new(x0, y0, x1, y1, tx, ty, tw, th) {
		this.x0 = x0;
		this.y0 = y0;
		this.x1 = x1;
		this.y1 = y1;
		this.tx = tx;
		this.ty = ty;
		this.tw = tw;
		this.th = th;
	}

	// its texture's pixels out of the image's (pw wide): the image itself when it is the whole
	public function pixels(src:Bytes, pw:Int):Bytes {
		if (tx == 0 && ty == 0 && tw == pw && src.length == tw * th * 4) return src;
		var b = Bytes.alloc(tw * th * 4);
		for (y in 0...th)
			b.blit(4 * y * tw, src, 4 * ((ty + y) * pw + tx), 4 * tw);
		return b;
	}
}
