package hxmc.ui.draw;

import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.text.GlyphAtlas;
import hxmc.ui.*;
import hxmc.ui.draw.DrawText;

// hxmc.ui's Canvas on hxmc.gfx: a frame's rectangles, shadows, glyphs and
// images become quads of one vertex buffer (UiShader: six vertices each),
// drawn in one call per run of quads with the same image (texture slot 1:
// an image's texture, else a white texel). Every vertex carries the clip (a rectangle in target pixels and
// its corner radius) that UiShader clips its fragments by, so clips need no
// scissor and rounded ones clip to their corners. The UI's pixels are scaled
// to the target's (scale: a Retina display's 2); glyphs are rasterized at the
// scaled size into the GlyphAtlas, uploaded to an R8 texture when it changed.
// An image is uploaded once (premultiplied, filtered linearly) and again
// when its version changes; forget(image) frees its texture.
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
	// the runs of quads by image texture: first vertex, count, image id (0: none)
	final batches:Array<Int> = [];
	final textures = new Map<Int, {texture:Texture, version:Int}>();
	var targetW = 1.0;
	var targetH = 1.0;

	// the state
	var tx = 0.0;
	var ty = 0.0;
	var alpha = 1.0;
	final alphas:Array<Float> = [];
	final clips:Array<Array<Float>> = []; // the clips pushed over: x0, y0, x1, y1, radius
	var clipX0 = 0.0;
	var clipY0 = 0.0;
	var clipX1 = 0.0;
	var clipY1 = 0.0;
	var clipR = 0.0;

	static inline var STRIDE = 108; // UiVertex: 27 floats

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
		clipX0 = clipY0 = clipR = 0;
		clipX1 = width;
		clipY1 = height;
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
			device.destroyBuffer(buffer);
			buffer = device.createBuffer({size: capacity, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, bytes, 0, used);
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, buffer);
		enc.setTexture(0, atlasTexture);
		var i = 0;
		while (i < batches.length) {
			var e = batches[i + 2] == 0 ? null : textures.get(batches[i + 2]);
			enc.setTexture(1, e == null ? blank : e.texture);
			enc.draw(batches[i + 1], 1, batches[i]);
			i += 3;
		}
	}

	// frees the texture of an image drawn before
	public function forget(img:Image) {
		var e = textures.get(img.id);
		if (e == null) return;
		device.destroyTexture(e.texture);
		textures.remove(img.id);
	}

	// the image's texture, uploaded (premultiplied) when new or changed
	function texture(img:Image):Texture {
		var e = textures.get(img.id);
		if (e != null && e.version == img.version) return e.texture;
		var px = img.pixels, n = img.width * img.height;
		var pre = haxe.io.Bytes.alloc(n * 4);
		for (k in 0...n) {
			var a = px.get(4 * k + 3);
			pre.set(4 * k, Std.int((px.get(4 * k) * a + 127) / 255));
			pre.set(4 * k + 1, Std.int((px.get(4 * k + 1) * a + 127) / 255));
			pre.set(4 * k + 2, Std.int((px.get(4 * k + 2) * a + 127) / 255));
			pre.set(4 * k + 3, a);
		}
		if (e == null) {
			e = {texture: device.createTexture({width: img.width, height: img.height, format: RGBA8, filter: Linear, data: pre}), version: img.version};
			textures.set(img.id, e);
		} else {
			device.writeTexture(e.texture, 0, 0, img.width, img.height, pre);
			e.version = img.version;
		}
		return e.texture;
	}

	// --- Canvas ---

	public function translate(dx:Float, dy:Float) {
		tx += dx;
		ty += dy;
	}

	// the clip becomes the intersection, with the new clip's radius where the
	// new clip is inside the old one (a rounded clip inside a rounded clip
	// that cuts into its corners keeps only the inner one's corners)
	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float) {
		clips.push([clipX0, clipY0, clipX1, clipY1, clipR]);
		var x0 = (x + tx) * scale, y0 = (y + ty) * scale, x1 = (x + w + tx) * scale, y1 = (y + h + ty) * scale;
		var inside = x0 >= clipX0 && y0 >= clipY0 && x1 <= clipX1 && y1 <= clipY1;
		var outside = x0 <= clipX0 && y0 <= clipY0 && x1 >= clipX1 && y1 >= clipY1;
		clipX0 = Math.max(clipX0, x0);
		clipY0 = Math.max(clipY0, y0);
		clipX1 = Math.min(clipX1, x1);
		clipY1 = Math.min(clipY1, y1);
		if (inside) clipR = radius * scale; else if (!outside) clipR = Math.min(clipR, radius * scale);
	}

	public function popClip() {
		var c = clips.pop();
		clipX0 = c[0];
		clipY0 = c[1];
		clipX1 = c[2];
		clipY1 = c[3];
		clipR = c[4];
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
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, radius * s, borderWidth * s, 0, 0, 1, 0);
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float) {
		if (w <= 0 || h <= 0 || color.a == 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		var m = blur * s + 1;
		if (culled(x0 - m, y0 - m, x1 + m, y1 + m)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, radius * s, 0, 3, blur * s, m, 0);
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		texture(img);
		quad(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, radius * s, 0, 2, 0, 1, img.id);
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
				var gx = (ox + lx + g.x + g.dx) * s, ix = Math.floor(gx);
				var sub = Std.int((gx - ix) * GlyphAtlas.SUBPIXELS);
				var a = atlas.get(g.font, g.id, size, sub);
				if (a.w == 0) continue;
				var qx = ix + a.left, qy = by + Math.round(g.dy * s) + a.top;
				if (culled(qx, qy, qx + a.w, qy + a.h)) continue;
				quad(qx, qy, qx + a.w, qy + a.h, a.x / atlas.width, a.y / atlas.height, (a.x + a.w) / atlas.width, (a.y + a.h) / atlas.height, color, 0, 0, 0,
					1, 0, 0, 0);
			}
		}
	}

	// --- vertices ---

	inline function culled(x0:Float, y0:Float, x1:Float, y1:Float)
		return x1 <= clipX0 || y1 <= clipY0 || x0 >= clipX1 || y0 >= clipY1 || clipX1 <= clipX0 || clipY1 <= clipY0;

	// a quad over x0, y0, x1, y1 grown by margin m (a rectangle's anti-aliased
	// edge, a shadow's blur), its texture coordinates growing with it
	function quad(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, radius:Float,
			borderWidth:Float, mode:Float, blur:Float, m:Float, image:Int) {
		// (a new run where the image changes)
		var nb = batches.length;
		if (nb == 0 || batches[nb - 1] != image) {
			batches.push(Std.int(used / STRIDE));
			batches.push(0);
			batches.push(image);
			nb += 3;
		}
		batches[nb - 2] += 6;
		if (used + 6 * STRIDE > bytes.length) {
			var b = Bytes.alloc(bytes.length * 2);
			b.blit(0, bytes, 0, used);
			bytes = b;
		}
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		var fa = fill.a / 255 * alpha, ba = border.a / 255 * alpha;
		var fr = fill.r / 255 * fa, fg = fill.g / 255 * fa, fb = fill.b / 255 * fa;
		var br = border.r / 255 * ba, bg = border.g / 255 * ba, bb = border.b / 255 * ba;
		var cx0 = clipX0, cy0 = clipY0, cx1 = clipX1, cy1 = clipY1, cr = clipR;
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
			bytes.setFloat(o + 76, blur);
			bytes.setFloat(o + 80, px);
			bytes.setFloat(o + 84, py);
			bytes.setFloat(o + 88, cr);
			bytes.setFloat(o + 92, cx0);
			bytes.setFloat(o + 96, cy0);
			bytes.setFloat(o + 100, cx1);
			bytes.setFloat(o + 104, cy1);
			used += STRIDE;
		}
		var mu = (u1 - u0) * m / (x1 - x0), mv = (v1 - v0) * m / (y1 - y0);
		vertex(ax, ay, u0 - mu, v0 - mv);
		vertex(ax, by, u0 - mu, v1 + mv);
		vertex(bx, ay, u1 + mu, v0 - mv);
		vertex(bx, ay, u1 + mu, v0 - mv);
		vertex(ax, by, u0 - mu, v1 + mv);
		vertex(bx, by, u1 + mu, v1 + mv);
	}
}
