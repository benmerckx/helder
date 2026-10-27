package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.text.GlyphAtlas;
import helder.ui.*;
import helder.ui.draw.DrawText;
import helder.image.Image;
import helder.image.PngDecoder;

// helder.ui's Canvas on helder.gfx: a frame's rectangles, shadows, glyphs and
// images become quads of one vertex buffer (UiShader: four vertices each,
// two triangles by a shared index buffer), drawn in one call per run of
// quads with the same image (texture slot 1:
// an image's texture, else a white texel). Every vertex carries the clip (a rectangle in target pixels and
// its corners' radii) that UiShader clips its fragments by, so clips need no
// scissor and rounded ones clip to their corners. The UI's pixels are scaled
// to the target's (scale: a Retina display's 2); glyphs are rasterized at the
// scaled size into the GlyphAtlas, its coverage uploaded into a texture's
// red channel (read at the nearest texel) where it changed. An image is
// uploaded once (premultiplied, filtered linearly) and again when its
// version changes; forget(image) frees its texture. Under a transform
// (pushTransform) a quad is built in the transform's scaled pixels (its
// scale: the square root of its determinant) and its corners turned into the
// target's by what remains (a rotation, or a skew), so that edges stay
// anti-aliased over a pixel; glyphs are rasterized at the scaled size, and
// read filtered where the transform turns them. A clip pushed under a turning
// transform clips to its bounds.
class Renderer implements Canvas {
	public final device:Device;
	public var scale = 1.0;
	public final atlas:GlyphAtlas;

	final pipeline:Pipeline;
	final atlasTexture:Texture;
	final blank:Texture;
	final nearest:Sampler;
	final linear:Sampler;
	// the shader's texture slots: the atlas's, the image's
	final atlasSlot:Int;
	final imageSlot:Int;
	var buffer:Buffer;
	var capacity:Int;
	var bytes:Bytes;
	var used = 0; // bytes of vertices this frame
	// (two triangles a quad: 0 1 2, 2 1 3 from each quad's first vertex; for so many quads)
	var indices:Null<Buffer> = null;
	var indexQuads = 0;
	// the runs of quads by image texture: first quad, count, key (the image id, twice, plus whether glyphs are filtered)
	final batches:Array<Int> = [];
	// (frame: the last one that drew it; one not drawn for EVICT frames is freed)
	final textures = new Map<Int, {texture:Texture, version:Int, frame:Int}>();
	var frames = 0;
	// the GPU textures drawn this frame (texture: by their negative ids), the passes to record before the frame's (beforePass)
	final gpu = new Map<Int, Texture>();
	final before:Array<Encoder->Void> = [];

	static inline var EVICT = 300;
	var targetW = 1.0;
	var targetH = 1.0;

	// the state
	var tx = 0.0;
	var ty = 0.0;
	var alpha = 1.0;
	final alphas:Array<Float> = [];
	final clips:Array<Array<Float>> = []; // the clips pushed over: x0, y0, x1, y1, the corners' radii
	var clipX0 = 0.0;
	var clipY0 = 0.0;
	var clipX1 = 0.0;
	var clipY1 = 0.0;
	// (its corners' radii: top left, top right, bottom right, bottom left)
	var clipR0 = 0.0;
	var clipR1 = 0.0;
	var clipR2 = 0.0;
	var clipR3 = 0.0;
	// the next quad's corners' radii and border sides (top, right, bottom, left), in its pixels
	var qr0 = 0.0;
	var qr1 = 0.0;
	var qr2 = 0.0;
	var qr3 = 0.0;
	var qw0 = 0.0;
	var qw1 = 0.0;
	var qw2 = 0.0;
	var qw3 = 0.0;
	// the transform pushed (target pixels from the scaled pixels after the
	// translation, scale, and transforms before it): m* (flat: none), its
	// scale (mk), whether it keeps glyphs on the pixel grid (aligned: no
	// turn, no skew, the same scale on both axes)
	var ma = 1.0;
	var mb = 0.0;
	var mc = 0.0;
	var md = 1.0;
	var me = 0.0;
	var mf = 0.0;
	var mk = 1.0;
	var flat = true;
	var aligned = true;
	final transforms:Array<Array<Float>> = [];

	static inline var STRIDE = 144; // UiVertex: 36 floats

	public function new(device:Device, ?atlas:GlyphAtlas) {
		this.device = device;
		this.atlas = atlas == null ? new GlyphAtlas(1024, 1024) : atlas;
		pipeline = device.createPipeline(UiShader.pipeline({blend: Premultiplied}));
		atlasTexture = device.createTexture({width: this.atlas.width, height: this.atlas.height, format: RGBA8});
		blank = device.createTexture({width: 1, height: 1, format: RGBA8, data: Bytes.ofHex("ffffffff")});
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
		atlasSlot = UiShader.textures[0].binding;
		imageSlot = UiShader.textures[1].binding;
		capacity = 4 * STRIDE * 1024;
		buffer = device.createBuffer({size: capacity, usage: Vertex});
		bytes = Bytes.alloc(capacity);
	}

	// starts a frame's drawing into a target of width x height pixels
	public function begin(width:Int, height:Int) {
		// (the textures of images no longer drawn: a replaced image, an svg drawn again at another size)
		frames++;
		if (frames % 60 == 0) {
			for (id => e in [for (k => v in textures) k => v])
				if (frames - e.frame > EVICT) {
					device.destroyTexture(e.texture);
					textures.remove(id);
				}
			for (p in [for (k in paths.keys()) k])
				if (frames - paths.get(p).frame > EVICT) paths.remove(p);
		}
		targetW = width;
		targetH = height;
		gpu.clear();
		before.resize(0);
		used = 0;
		batches.resize(0);
		tx = ty = 0;
		alpha = 1;
		alphas.resize(0);
		clips.resize(0);
		transforms.resize(0);
		ma = md = mk = 1;
		mb = mc = me = mf = 0;
		flat = aligned = true;
		clipX0 = clipY0 = clipR0 = clipR1 = clipR2 = clipR3 = 0;
		clipX1 = width;
		clipY1 = height;
	}

	// uploads and draws what was drawn since begin, in the pass the encoder is in
	public function end(enc:Encoder) {
		if (atlas.dirtyX1 > atlas.dirtyX0) {
			var x = atlas.dirtyX0, y = atlas.dirtyY0, w = atlas.dirtyX1 - x, h = atlas.dirtyY1 - y;
			// (coverage in the red channel)
			var region = Bytes.alloc(w * h * 4);
			for (r in 0...h) {
				var src = (y + r) * atlas.width + x, dst = r * w * 4;
				for (c in 0...w)
					region.set(dst + c * 4, atlas.pixels.get(src + c));
			}
			device.writeTexture(atlasTexture, region, x, y, w, h);
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
		var quads = Std.int(used / (4 * STRIDE));
		if (quads > indexQuads) {
			var n = indexQuads == 0 ? 4096 : indexQuads;
			while (n < quads)
				n *= 2;
			var ib = Bytes.alloc(n * 6 * 4);
			for (q in 0...n) {
				var v = q * 4, o = q * 24;
				ib.setInt32(o, v);
				ib.setInt32(o + 4, v + 1);
				ib.setInt32(o + 8, v + 2);
				ib.setInt32(o + 12, v + 2);
				ib.setInt32(o + 16, v + 1);
				ib.setInt32(o + 20, v + 3);
			}
			if (indices != null) device.destroyBuffer(indices);
			indices = device.createBuffer({size: ib.length, usage: Index, data: ib});
			indexQuads = n;
		}
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, buffer);
		enc.setIndexBuffer(indices, UInt32);
		var i = 0;
		while (i < batches.length) {
			// (a run's key: its image id, twice, plus whether glyphs are read filtered)
			var key = batches[i + 2], image = key >> 1;
			var e = image <= 0 ? null : textures.get(image);
			enc.setTexture(atlasSlot, atlasTexture, key & 1 == 1 ? linear : nearest);
			enc.setTexture(imageSlot, image < 0 ? gpu.get(image) : e == null ? blank : e.texture, linear);
			enc.drawIndexed(batches[i + 1] * 6, 1, batches[i] * 6, 0);
			i += 3;
		}
	}

	// f records a pass of its own before the frame's (prepare): what a
	// texture drawn this frame shows, rendered first (a <Scene>'s)
	public function beforePass(f:Encoder->Void)
		before.push(f);

	// records the passes asked for since begin, outside the frame's pass (UiWindow: after painting, before it)
	public function prepare(enc:Encoder) {
		for (f in before)
			f(enc);
		before.resize(0);
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
		if (e != null) e.frame = frames;
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
			e = {texture: device.createTexture({width: img.width, height: img.height, format: RGBA8, data: pre}), version: img.version, frame: frames};
			textures.set(img.id, e);
		} else {
			device.writeTexture(e.texture, pre);
			e.version = img.version;
		}
		return e.texture;
	}

	// --- Canvas ---

	public function translate(dx:Float, dy:Float) {
		tx += dx;
		ty += dy;
	}

	// the clip becomes the intersection, with the new clip's radii where the
	// new clip is inside the old one (a rounded clip inside a rounded clip
	// that cuts into its corners keeps only the inner one's corners), else
	// the smaller of each
	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		clips.push([clipX0, clipY0, clipX1, clipY1, clipR0, clipR1, clipR2, clipR3]);
		var k = scale;
		var x0 = (x + tx) * scale, y0 = (y + ty) * scale, x1 = (x + w + tx) * scale, y1 = (y + h + ty) * scale;
		if (!flat) {
			// (the transformed corners' bounds)
			var k = mk, ra = ma / k, rb = mb / k, rc = mc / k, rd = md / k;
			x0 *= k;
			y0 *= k;
			x1 *= k;
			y1 *= k;
			var ax = ra * x0 + rc * y0, bx = ra * x1 + rc * y0, cx = ra * x0 + rc * y1, dx = ra * x1 + rc * y1;
			var ay = rb * x0 + rd * y0, by = rb * x1 + rd * y0, cy = rb * x0 + rd * y1, dy = rb * x1 + rd * y1;
			x0 = Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me;
			x1 = Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me;
			y0 = Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf;
			y1 = Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf;
			k *= mk;
		}
		var inside = x0 >= clipX0 && y0 >= clipY0 && x1 <= clipX1 && y1 <= clipY1;
		var outside = x0 <= clipX0 && y0 <= clipY0 && x1 >= clipX1 && y1 >= clipY1;
		clipX0 = Math.max(clipX0, x0);
		clipY0 = Math.max(clipY0, y0);
		clipX1 = Math.min(clipX1, x1);
		clipY1 = Math.min(clipY1, y1);
		var c0 = (corners == null ? radius : corners.topLeft) * k, c1 = (corners == null ? radius : corners.topRight) * k;
		var c2 = (corners == null ? radius : corners.bottomRight) * k, c3 = (corners == null ? radius : corners.bottomLeft) * k;
		// (scaled down together as CSS's, where a side's two add up to more than it: fit)
		var f = 1.0, cw = w * k, ch = h * k;
		if (c0 + c1 > cw && c0 + c1 > 0) f = Math.min(f, cw / (c0 + c1));
		if (c3 + c2 > cw && c3 + c2 > 0) f = Math.min(f, cw / (c3 + c2));
		if (c0 + c3 > ch && c0 + c3 > 0) f = Math.min(f, ch / (c0 + c3));
		if (c1 + c2 > ch && c1 + c2 > 0) f = Math.min(f, ch / (c1 + c2));
		c0 *= f;
		c1 *= f;
		c2 *= f;
		c3 *= f;
		if (inside) {
			clipR0 = c0;
			clipR1 = c1;
			clipR2 = c2;
			clipR3 = c3;
		} else if (!outside) {
			clipR0 = Math.min(clipR0, c0);
			clipR1 = Math.min(clipR1, c1);
			clipR2 = Math.min(clipR2, c2);
			clipR3 = Math.min(clipR3, c3);
		}
	}

	public function popClip() {
		var c = clips.pop();
		clipX0 = c[0];
		clipY0 = c[1];
		clipX1 = c[2];
		clipY1 = c[3];
		clipR0 = c[4];
		clipR1 = c[5];
		clipR2 = c[6];
		clipR3 = c[7];
	}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		transforms.push([ma, mb, mc, md, me, mf, mk, flat ? 1 : 0, aligned ? 1 : 0]);
		// (in the scaled pixels after the translation: moved to it, transformed, moved back)
		var s = scale;
		var ne = s * (e - a * tx - c * ty + tx), nf = s * (f - b * tx - d * ty + ty);
		var na = ma * a + mc * b, nb = mb * a + md * b, nc = ma * c + mc * d, nd = mb * c + md * d;
		var e2 = ma * ne + mc * nf + me, f2 = mb * ne + md * nf + mf;
		ma = na;
		mb = nb;
		mc = nc;
		md = nd;
		me = e2;
		mf = f2;
		mk = Math.sqrt(Math.abs(ma * md - mb * mc));
		flat = ma == 1 && mb == 0 && mc == 0 && md == 1 && me == 0 && mf == 0;
		aligned = mb == 0 && mc == 0 && ma == md && ma > 0;
	}

	public function popTransform() {
		var t = transforms.pop();
		ma = t[0];
		mb = t[1];
		mc = t[2];
		md = t[3];
		me = t[4];
		mf = t[5];
		mk = t[6];
		flat = t[7] == 1;
		aligned = t[8] == 1;
	}

	public function pushOpacity(a:Float) {
		alphas.push(alpha);
		alpha *= a;
	}

	public function popOpacity()
		alpha = alphas.pop();

	// (the next quad's corners: each corner's, else radius; sides: each side's, else width; in device pixels)
	inline function corners(c:Null<Corners>, radius:Float) {
		var s = scale;
		qr0 = (c == null ? radius : c.topLeft) * s;
		qr1 = (c == null ? radius : c.topRight) * s;
		qr2 = (c == null ? radius : c.bottomRight) * s;
		qr3 = (c == null ? radius : c.bottomLeft) * s;
	}

	// (the corners scaled down together where two of a side's add up to
	// more than it, as CSS's border-radius: a huge radius a pill, not an ellipse)
	inline function fit(w:Float, h:Float) {
		var f = 1.0;
		inline function side(len:Float, a:Float, b:Float)
			if (a + b > len && a + b > 0) f = Math.min(f, len / (a + b));
		side(w, qr0, qr1);
		side(w, qr3, qr2);
		side(h, qr0, qr3);
		side(h, qr1, qr2);
		if (f < 1) {
			qr0 *= f;
			qr1 *= f;
			qr2 *= f;
			qr3 *= f;
		}
	}

	inline function sides(e:Null<Edges>, width:Float) {
		var s = scale;
		qw0 = (e == null ? width : e.top) * s;
		qw1 = (e == null ? width : e.right) * s;
		qw2 = (e == null ? width : e.bottom) * s;
		qw3 = (e == null ? width : e.left) * s;
	}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		this.sides(sides, borderWidth);
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, 0, 0, 0, 0);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, fill, border, 0, 0, 1, 0);
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {
		if (w <= 0 || h <= 0 || color.a == 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		// (the box casting it, not shaded: its offset and the spread)
		if (offset != null) {
			qw0 = offset[0] * s;
			qw1 = offset[1] * s;
			qw2 = offset[2] * s;
			qw3 = 1;
		} else sides(null, 0);
		// (CSS's blur: a Gaussian whose standard deviation is half of it, drawn out to three of them)
		var sigma = blur * s / 2;
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 3, sigma, 3 * sigma, 0);
			return;
		}
		var m = 3 * sigma + 1;
		if (culled(x0 - m, y0 - m, x1 + m, y1 + m)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 3, sigma, m, 0);
	}

	// an inset shadow in a padding box x, y, w, h (its corners): darkened from
	// outside the box moved by dx, dy and shrunk by spread, blurred
	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners) {
		if (w <= 0 || h <= 0 || color.a == 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		qw0 = dx * s;
		qw1 = dy * s;
		qw2 = spread * s;
		qw3 = 0;
		var sigma = blur * s / 2;
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 4, sigma, 0, 0);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 0, 0, color, 0, 4, sigma, 1, 0);
	}

	// (a path rasterized at the scale it is drawn at, its stroke's reach
	// around it, kept while it is drawn the same way: by path, its paints and the scale)
	final paths = new haxe.ds.ObjectMap<Path, {key:String, img:Image, x:Float, y:Float, frame:Int}>();

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		var b = p.bounds(), s = scale;
		var reach = stroke == null ? 0.0 : stroke.width / 2 * ((stroke.join ?? Miter) == Miter ? Math.max(1, stroke.miterLimit ?? 4) : 1.5);
		var x0 = Math.floor((b.x - reach) * s) - 1, y0 = Math.floor((b.y - reach) * s) - 1;
		var w = Std.int(Math.ceil((b.x + b.width + reach) * s) + 1 - x0), h = Std.int(Math.ceil((b.y + b.height + reach) * s) + 1 - y0);
		if (w <= 0 || h <= 0 || w * h > 4096 * 4096) return;
		var key = s + "/" + p.commands.length + "/" + p.evenOdd + "/" + Std.string(fill) + "/" + (stroke == null ? "" : stroke.width + Std.string(stroke.paint)
			+ stroke.cap + stroke.join + stroke.miterLimit + stroke.dashes + stroke.dashOffset);
		var e = paths.get(p);
		if (e == null || e.key != key) {
			e = {key: key, img: p.render(w, h, [s, 0, 0, s, -x0, -y0], fill, stroke), x: x0 / s, y: y0 / s, frame: frames};
			paths.set(p, e);
		}
		e.frame = frames;
		image(e.img, e.x, e.y, w / s, h / s, 0, 0, 1, 1, 0);
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		sides(null, 0);
		if (!flat) {
			texture(img);
			shape(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, 2, 0, 0, img.id);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		texture(img);
		quad(x0, y0, x1, y1, u0, v0, u1, v1, Color.WHITE, 0, 2, 0, 1, img.id);
	}

	// a GPU texture (a render target, rows top to bottom: a <Scene>'s) at x, y, w x h; id names it, negative, one per texture
	public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius = 0.0, ?corners:Corners) {
		if (w <= 0 || h <= 0 || id >= 0) return;
		gpu.set(id, t);
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		this.corners(corners, radius);
		fit(x1 - x0, y1 - y0);
		sides(null, 0);
		if (!flat) {
			shape(x0, y0, x1, y1, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 0, id);
			return;
		}
		if (culled(x0 - 1, y0 - 1, x1 + 1, y1 + 1)) return;
		quad(x0, y0, x1, y1, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1, id);
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		glyphs(p, x, y, width, align, color, colors, -1);

	// (a text shadow's glyphs: their outlines, a colour font's too, in its
	// colour, blurred: CSS's blur, the Gaussian's standard deviation half of
	// it; a colour bitmap's glyph has none and casts none)
	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		glyphs(p, x, y, width, align, color, colors, blur);

	// (blur < 0: the text itself)
	function glyphs(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, colors:Null<Array<Color>>, blur:Float) {
		var dp = cast(p, DrawParagraph);
		var t = dp.layout, s = scale;
		var size = t.fonts.size * s;
		var ox = x + tx, oy = y + ty;
		if (!flat) {
			if (mk < 1e-6) return;
			// (in the scaled pixels: on the target's grid where aligned)
			s *= mk;
			size *= mk;
		}
		// (a shadow's blur in device pixels, to a quarter: the atlas keeps each; how far it reaches)
		var sigma = blur > 0 ? Math.round(blur * s / 2 * 4) / 4 : 0.0, reach = 3 * sigma;
		for (l in t.lines) {
			var lx = switch align {
				case Center: (width - l.width) / 2;
				case Right: width - l.width;
				case _: 0.0;
			}
			var by = Math.round((oy + l.top + l.baseline) * s + (flat ? 0 : mf - Std.int(mf)));
			if (flat && (by - size * 1.5 - reach > clipY1 || by + size + reach < clipY0)) continue;
			for (i in l.glyphStart...l.glyphEnd) {
				var c = t.glyphChar(i);
				if (c == 32 || c == 10 || c == 9 || t.glyphHidden(i)) continue;
				var id = t.glyphId(i), run = t.glyphRun(i);
				var gx = (ox + lx + t.glyphX(i) + t.glyphOffsetX(i)) * s, gy = by + Math.round(t.glyphOffsetY(i) * s);
				var f = t.glyphFont(i);
				// (a run's glyphs: its size and colour)
				var set = t.glyphFontSet(i);
				var size = run < 0 ? size : set.size * s, oblique = set.oblique;
				var color = run >= 0 && colors != null && run < colors.length ? colors[run] : color;
				if (f.hasColor && blur < 0) {
					// (colour layers: each its glyph in its colour; else a colour bitmap)
					var layers = f.colorLayers(id);
					if (layers != null) {
						for (layer in layers)
							glyph(f, layer.glyph, size, gx, gy, layer.color == -1 ? color : (layer.color : Color), oblique);
						continue;
					}
					var b = colorGlyph(f, id, size);
					if (b != null) {
						var ex = flat ? 0.0 : me - Std.int(me), ey = flat ? 0.0 : mf - Std.int(mf);
						var qx = Math.round(gx + b.left + ex) - ex, qy = gy - b.top - ey;
						if (!flat || !culled(qx, qy, qx + b.image.width, qy + b.image.height)) {
							texture(b.image);
							qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
							quad(qx, qy, qx + b.image.width, qy + b.image.height, 0, 0, 1, 1, Color.WHITE, 0, 2, 0, 1, b.image.id);
						}
						continue;
					}
				}
				glyph(f, id, size, gx, gy, color, oblique, sigma);
			}
		}
	}

	// a glyph from the atlas at (gx, gy): device pixels, the baseline
	// (under a transform: scaled pixels, gy whole on the target's grid less
	// the translation's fraction, which the glyph is moved back by)
	inline function glyph(f:helder.text.FontFile, id:Int, size:Float, gx:Float, gy:Int, color:Color, oblique:Bool, sigma = 0.0) {
		// (aligned: the subpixel offset on the target's grid, as the transform moves it;
		// the position rounded to the nearest of the atlas's steps, not down, as Skia's)
		var ex = flat ? 0.0 : me - Std.int(me), ey = flat ? 0.0 : mf - Std.int(mf);
		var px = gx + ex + 0.5 / GlyphAtlas.SUBPIXELS, ix = Math.floor(px);
		var sub = Std.int((px - ix) * GlyphAtlas.SUBPIXELS);
		var a = atlas.get(f, id, size, sub, oblique, sigma);
		if (a.w > 0) {
			var qx = ix - ex + a.left, qy = gy + a.top - ey;
			if (!flat || !culled(qx, qy, qx + a.w, qy + a.h)) {
				qr0 = qr1 = qr2 = qr3 = qw0 = qw1 = qw2 = qw3 = 0;
				quad(qx, qy, qx + a.w, qy + a.h, a.x / atlas.width, a.y / atlas.height, (a.x + a.w) / atlas.width, (a.y + a.h) / atlas.height, color, 0, 1, 0, 0,
					0);
			}
		}
	}

	// a colour bitmap glyph at a size (device pixels): its PNG decoded and
	// scaled down (averaged over each pixel's area, as a browser draws it
	// small), kept per face, glyph and size; its place from the origin
	final colorGlyphs = new Map<String, Null<{image:Image, left:Float, top:Int}>>();

	function colorGlyph(f:helder.text.FontFile, id:Int, size:Float):Null<{image:Image, left:Float, top:Int}> {
		var key = f.id + ":" + id + ":" + size;
		if (colorGlyphs.exists(key)) return colorGlyphs.get(key);
		var r:Null<{image:Image, left:Float, top:Int}> = null;
		var b = f.colorBitmap(id, size);
		if (b != null) {
			var d = try PngDecoder.decode(b.png) catch (e:Dynamic) null;
			if (d != null) {
				var k = size / b.ppem;
				var w = Std.int(Math.max(1, Math.round(d.width * k))), h = Std.int(Math.max(1, Math.round(d.height * k)));
				r = {image: new Image(w, h, scaleDown(d.rgba, d.width, d.height, w, h)), left: b.left * k, top: Math.round(b.top * k)};
			}
		}
		colorGlyphs.set(key, r);
		return r;
	}

	// RGBA8 pixels (straight alpha) to a smaller size: each pixel the
	// average of the source area it covers, weighted by alpha
	static function scaleDown(src:Bytes, sw:Int, sh:Int, w:Int, h:Int):Bytes {
		var out = Bytes.alloc(w * h * 4);
		var fx = sw / w, fy = sh / h;
		for (y in 0...h) {
			var y0 = y * fy, y1 = y0 + fy;
			for (x in 0...w) {
				var x0 = x * fx, x1 = x0 + fx;
				var r = 0.0, g = 0.0, b = 0.0, a = 0.0, area = 0.0;
				var sy = Std.int(y0);
				while (sy < y1 && sy < sh) {
					var wy = Math.min(y1, sy + 1) - Math.max(y0, sy);
					var sx = Std.int(x0);
					while (sx < x1 && sx < sw) {
						var wgt = (Math.min(x1, sx + 1) - Math.max(x0, sx)) * wy;
						var o = 4 * (sy * sw + sx), al = src.get(o + 3) * wgt;
						r += src.get(o) * al;
						g += src.get(o + 1) * al;
						b += src.get(o + 2) * al;
						a += al;
						area += wgt;
						sx++;
					}
					sy++;
				}
				var o = 4 * (y * w + x);
				if (a > 0) {
					out.set(o, Std.int(r / a + 0.5));
					out.set(o + 1, Std.int(g / a + 0.5));
					out.set(o + 2, Std.int(b / a + 0.5));
				}
				out.set(o + 3, Std.int(a / area + 0.5));
			}
		}
		return out;
	}

	// --- vertices ---

	inline function culled(x0:Float, y0:Float, x1:Float, y1:Float)
		return x1 <= clipX0 || y1 <= clipY0 || x0 >= clipX1 || y0 >= clipY1 || clipX1 <= clipX0 || clipY1 <= clipY0;

	// a rectangle, shadow or image under a transform: from device pixels to
	// the scaled ones (lengths too), culled by its turned corners' bounds;
	// blur: the margin it grows by before its anti-aliased pixel
	function shape(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Float, blur:Float,
			grow:Float, image:Int) {
		var k = mk;
		if (k < 1e-6) return;
		x0 *= k;
		y0 *= k;
		x1 *= k;
		y1 *= k;
		var m = grow * k + 1;
		var ra = ma / k, rb = mb / k, rc = mc / k, rd = md / k;
		var lx = x0 - m, ly = y0 - m, hx = x1 + m, hy = y1 + m;
		var ax = ra * lx + rc * ly, bx = ra * hx + rc * ly, cx = ra * lx + rc * hy, dx = ra * hx + rc * hy;
		var ay = rb * lx + rd * ly, by = rb * hx + rd * ly, cy = rb * lx + rd * hy, dy = rb * hx + rd * hy;
		if (culled(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me, Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf,
			Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me, Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf))
			return;
		qr0 *= k;
		qr1 *= k;
		qr2 *= k;
		qr3 *= k;
		qw0 *= k;
		qw1 *= k;
		qw2 *= k;
		qw3 *= k;
		quad(x0, y0, x1, y1, u0, v0, u1, v1, fill, border, mode, blur * k, m, image);
	}

	// a quad over x0, y0, x1, y1 grown by margin m (a rectangle's anti-aliased
	// edge, a shadow's blur), its texture coordinates growing with it; its
	// corners and border sides: qr*, qw*
	function quad(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Float, blur:Float,
			m:Float, image:Int) {
		// (a new run where the image changes, or how glyphs are read)
		var key = image * 2 + (mode == 1 && !aligned ? 1 : 0);
		var nb = batches.length;
		if (nb == 0 || batches[nb - 1] != key) {
			batches.push(Std.int(used / (4 * STRIDE)));
			batches.push(0);
			batches.push(key);
			nb += 3;
		}
		batches[nb - 2]++;
		if (used + 4 * STRIDE > bytes.length) {
			var b = Bytes.alloc(bytes.length * 2);
			b.blit(0, bytes, 0, used);
			bytes = b;
		}
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		var fa = fill.a / 255 * alpha, ba = border.a / 255 * alpha;
		var fr = fill.r / 255 * fa, fg = fill.g / 255 * fa, fb = fill.b / 255 * fa;
		var br = border.r / 255 * ba, bg = border.g / 255 * ba, bb = border.b / 255 * ba;
		var cx0 = clipX0, cy0 = clipY0, cx1 = clipX1, cy1 = clipY1, c0 = clipR0, c1 = clipR1, c2 = clipR2, c3 = clipR3;
		var r0 = qr0, r1 = qr1, r2 = qr2, r3 = qr3, w0 = qw0, w1 = qw1, w2 = qw2, w3 = qw3;
		// (the transform less its scale: exact for none)
		var k = mk, ra = flat ? 1 : ma / k, rb = flat ? 0 : mb / k, rc = flat ? 0 : mc / k, rd = flat ? 1 : md / k, te = flat ? 0 : me, tf = flat ? 0 : mf;
		inline function vertex(px:Float, py:Float, u:Float, v:Float) {
			var o = used;
			var X = ra * px + rc * py + te, Y = rb * px + rd * py + tf;
			bytes.setFloat(o, X / targetW * 2 - 1);
			bytes.setFloat(o + 4, 1 - Y / targetH * 2);
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
			bytes.setFloat(o + 64, r0);
			bytes.setFloat(o + 68, r1);
			bytes.setFloat(o + 72, r2);
			bytes.setFloat(o + 76, r3);
			bytes.setFloat(o + 80, w0);
			bytes.setFloat(o + 84, w1);
			bytes.setFloat(o + 88, w2);
			bytes.setFloat(o + 92, w3);
			bytes.setFloat(o + 96, mode);
			bytes.setFloat(o + 100, blur);
			bytes.setFloat(o + 104, X);
			bytes.setFloat(o + 108, Y);
			bytes.setFloat(o + 112, cx0);
			bytes.setFloat(o + 116, cy0);
			bytes.setFloat(o + 120, cx1);
			bytes.setFloat(o + 124, cy1);
			bytes.setFloat(o + 128, c0);
			bytes.setFloat(o + 132, c1);
			bytes.setFloat(o + 136, c2);
			bytes.setFloat(o + 140, c3);
			used += STRIDE;
		}
		// (the other corners: the first copied, what differs written over it)
		inline function corner(px:Float, py:Float, u:Float, v:Float) {
			var o = used;
			bytes.blit(o, bytes, o - STRIDE, STRIDE);
			var X = ra * px + rc * py + te, Y = rb * px + rd * py + tf;
			bytes.setFloat(o, X / targetW * 2 - 1);
			bytes.setFloat(o + 4, 1 - Y / targetH * 2);
			bytes.setFloat(o + 8, px - x0 - hx);
			bytes.setFloat(o + 12, py - y0 - hy);
			bytes.setFloat(o + 24, u);
			bytes.setFloat(o + 28, v);
			bytes.setFloat(o + 104, X);
			bytes.setFloat(o + 108, Y);
			used += STRIDE;
		}
		var mu = (u1 - u0) * m / (x1 - x0), mv = (v1 - v0) * m / (y1 - y0);
		vertex(ax, ay, u0 - mu, v0 - mv);
		corner(ax, by, u0 - mu, v1 + mv);
		corner(bx, ay, u1 + mu, v0 - mv);
		corner(bx, by, u1 + mu, v1 + mv);
	}
}
