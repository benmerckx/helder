package hxmc.ui.draw;

import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.text.GlyphAtlas;
import hxmc.ui.*;
import hxmc.ui.draw.DrawText;

// hxmc.ui's Canvas on hxmc.gfx: a frame's rectangles and glyphs become
// quads of one vertex buffer (UiShader: six vertices each), drawn in
// batches split where the clip (a scissor rectangle) changes. The UI's
// pixels are scaled to the target's (scale: a Retina display's 2); glyphs
// are rasterized at the scaled size into the GlyphAtlas, uploaded to an R8
// texture when it changed. Rounded clips clip to their rectangle.
class Renderer implements Canvas {
	public final device:Device;
	public var scale = 1.0;
	public final atlas:GlyphAtlas;

	final pipeline:Pipeline;
	final atlasTexture:Texture;
	final blank:Texture;
	var buffer:Buffer;
	var capacity:Int;
	var bytes:Bytes;
	var used = 0; // bytes of vertices this frame
	final batches:Array<Int> = []; // first vertex, count, scissor x, y, w, h: 6 Ints each
	var targetW = 1.0;
	var targetH = 1.0;

	// the state
	var tx = 0.0;
	var ty = 0.0;
	var alpha = 1.0;
	final alphas:Array<Float> = [];
	final clips:Array<Array<Float>> = []; // x0, y0, x1, y1 (target pixels) and the translation at push
	var clipX0 = 0.0;
	var clipY0 = 0.0;
	var clipX1 = 0.0;
	var clipY1 = 0.0;

	static inline var STRIDE = 80; // UiVertex: 20 floats

	public function new(device:Device, ?atlas:GlyphAtlas) {
		this.device = device;
		this.atlas = atlas == null ? new GlyphAtlas(1024, 1024) : atlas;
		pipeline = device.createPipeline(UiShader.pipeline({blend: Premultiplied}));
		atlasTexture = device.createTexture({width: this.atlas.width, height: this.atlas.height, format: R8, filter: Nearest});
		blank = device.createTexture({width: 1, height: 1, format: RGBA8, filter: Nearest, data: Bytes.ofHex("ffffffff")});
		capacity = 6 * STRIDE * 1024;
		buffer = device.createBuffer({size: capacity, usage: Vertex});
		bytes = Bytes.alloc(capacity);
	}

	// starts a frame's drawing into a target of width x height pixels
	public function begin(width:Int, height:Int) {
		targetW = width;
		targetH = height;
		used = 0;
		batches.resize(0);
		tx = ty = 0;
		alpha = 1;
		alphas.resize(0);
		clips.resize(0);
		clipX0 = clipY0 = 0;
		clipX1 = width;
		clipY1 = height;
		newBatch();
	}

	// uploads and draws what was drawn since begin, in the pass the encoder is in
	public function end(enc:Encoder) {
		if (atlas.dirtyX1 > atlas.dirtyX0) {
			var x = atlas.dirtyX0, y = atlas.dirtyY0, w = atlas.dirtyX1 - x, h = atlas.dirtyY1 - y;
			var region = Bytes.alloc(w * h);
			for (r in 0...h)
				region.blit(r * w, atlas.pixels, (y + r) * atlas.width + x, w);
			device.writeTexture(atlasTexture, x, y, w, h, region);
			atlas.clean();
		}
		if (used == 0) return;
		if (used > capacity) {
			while (capacity < used)
				capacity *= 2;
			buffer = device.createBuffer({size: capacity, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, bytes, 0, used);
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, buffer);
		enc.setTexture(0, atlasTexture);
		enc.setTexture(1, blank);
		var i = 0;
		while (i < batches.length) {
			var count = batches[i + 1];
			if (count > 0 && batches[i + 4] > 0 && batches[i + 5] > 0) {
				enc.setScissor(batches[i + 2], batches[i + 3], batches[i + 4], batches[i + 5]);
				enc.draw(count, 1, batches[i]);
			}
			i += 6;
		}
		enc.setScissor(0, 0, Std.int(targetW), Std.int(targetH));
	}

	// --- Canvas ---

	public function translate(dx:Float, dy:Float) {
		tx += dx;
		ty += dy;
	}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float) {
		clips.push([clipX0, clipY0, clipX1, clipY1]);
		var x0 = (x + tx) * scale, y0 = (y + ty) * scale, x1 = (x + w + tx) * scale, y1 = (y + h + ty) * scale;
		clipX0 = Math.max(clipX0, x0);
		clipY0 = Math.max(clipY0, y0);
		clipX1 = Math.min(clipX1, x1);
		clipY1 = Math.min(clipY1, y1);
		newBatch();
	}

	public function popClip() {
		var c = clips.pop();
		clipX0 = c[0];
		clipY0 = c[1];
		clipX1 = c[2];
		clipY1 = c[3];
		newBatch();
	}

	public function pushOpacity(a:Float) {
		alphas.push(alpha);
		alpha *= a;
	}

	public function popOpacity()
		alpha = alphas.pop();

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		if (x1 <= clipX0 || y1 <= clipY0 || x0 >= clipX1 || y0 >= clipY1) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, radius * s, borderWidth * s, 0);
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color) {
		var dp = cast(p, DrawParagraph);
		var t = dp.layout, s = scale;
		var size = t.fonts.size * s;
		var ox = x + tx, oy = y + ty;
		for (l in t.lines) {
			var lx = switch align {
				case Center: (width - l.width) / 2;
				case Right: width - l.width;
				case _: 0.0;
			}
			var by = Math.round((oy + l.top + t.baseline) * s);
			if (by - size * 1.5 > clipY1 || by + size < clipY0) continue;
			for (g in l.glyphs) {
				if (g.cp == 32 || g.cp == 10 || g.cp == 9) continue;
				var gx = (ox + lx + g.x) * s, ix = Math.floor(gx);
				var sub = Std.int((gx - ix) * GlyphAtlas.SUBPIXELS);
				var a = atlas.get(g.font, g.id, size, sub);
				if (a.w == 0) continue;
				var qx = ix + a.left, qy = by + a.top;
				if (qx + a.w <= clipX0 || qx >= clipX1 || qy + a.h <= clipY0 || qy >= clipY1) continue;
				quad(qx, qy, qx + a.w, qy + a.h, a.x / atlas.width, a.y / atlas.height, (a.x + a.w) / atlas.width, (a.y + a.h) / atlas.height, color, 0, 0, 0, 1);
			}
		}
	}

	// --- vertices ---

	function newBatch() {
		var n = batches.length;
		var first = Std.int(used / STRIDE);
		var sx = Std.int(Math.max(0, Math.floor(clipX0))), sy = Std.int(Math.max(0, Math.floor(clipY0)));
		var sw = Std.int(Math.max(0, Math.ceil(clipX1) - sx)), sh = Std.int(Math.max(0, Math.ceil(clipY1) - sy));
		// (an empty batch is replaced)
		if (n > 0 && batches[n - 5] == 0) {
			batches[n - 6] = first;
			batches[n - 4] = sx;
			batches[n - 3] = sy;
			batches[n - 2] = sw;
			batches[n - 1] = sh;
			return;
		}
		for (v in [first, 0, sx, sy, sw, sh])
			batches.push(v);
	}

	function quad(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, radius:Float,
			borderWidth:Float, mode:Float) {
		if (used + 6 * STRIDE > bytes.length) {
			var b = Bytes.alloc(bytes.length * 2);
			b.blit(0, bytes, 0, used);
			bytes = b;
		}
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		// (a pixel of margin around a rectangle for its anti-aliased edge)
		var m = mode == 0 ? 1.0 : 0.0;
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		var fa = fill.a / 255 * alpha, ba = border.a / 255 * alpha;
		var fr = fill.r / 255 * fa, fg = fill.g / 255 * fa, fb = fill.b / 255 * fa;
		var br = border.r / 255 * ba, bg = border.g / 255 * ba, bb = border.b / 255 * ba;
		inline function vertex(px:Float, py:Float, u:Float, v:Float) {
			var o = used;
			bytes.setFloat(o, px / targetW * 2 - 1);
			bytes.setFloat(o + 4, 1 - py / targetH * 2);
			bytes.setFloat(o + 8, px - x0 - hx);
			bytes.setFloat(o + 12, py - y0 - hy);
			bytes.setFloat(o + 16, hx);
			bytes.setFloat(o + 20, hy);
			bytes.setFloat(o + 24, u);
			bytes.setFloat(o + 28, v);
			bytes.setFloat(o + 32, fr);
			bytes.setFloat(o + 36, fg);
			bytes.setFloat(o + 40, fb);
			bytes.setFloat(o + 44, fa);
			bytes.setFloat(o + 48, br);
			bytes.setFloat(o + 52, bg);
			bytes.setFloat(o + 56, bb);
			bytes.setFloat(o + 60, ba);
			bytes.setFloat(o + 64, radius);
			bytes.setFloat(o + 68, borderWidth);
			bytes.setFloat(o + 72, mode);
			bytes.setFloat(o + 76, 0);
			used += STRIDE;
		}
		var du = (u1 - u0), dv = (v1 - v0);
		var mu = mode == 0 ? 0 : du * m / (x1 - x0), mv = mode == 0 ? 0 : dv * m / (y1 - y0);
		vertex(ax, ay, u0 - mu, v0 - mv);
		vertex(ax, by, u0 - mu, v1 + mv);
		vertex(bx, ay, u1 + mu, v0 - mv);
		vertex(bx, ay, u1 + mu, v0 - mv);
		vertex(ax, by, u0 - mu, v1 + mv);
		vertex(bx, by, u1 + mu, v1 + mv);
		batches[batches.length - 5] += 6;
	}
}
