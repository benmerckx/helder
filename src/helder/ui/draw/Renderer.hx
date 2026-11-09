package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.text.GlyphAtlas;
import helder.ui.*;
import helder.ui.Paint;
import helder.ui.Stroke;
import helder.ui.draw.DrawText;
import helder.image.Image;
import helder.image.PngDecoder;
import helder.image.Resize;
import helder.ui.draw.UiShader;

// helder.ui's Canvas on helder.gfx: a frame's rectangles, borders, shadows,
// glyphs and images are instances of one quad (UiShader's, after Rune's
// uber-quad: anomalyco/rune, MIT), each a kind of it, all in one instance
// buffer (helder.gfx's QuadBatch, instanced; the batcher SpriteBatch is on
// too), in the order drawn, and drawn as one instanced draw: a frame is one
// draw call, one pipeline. What would split it is shared instead: every
// instance carries the clip (a rectangle in target pixels and its corners'
// radii) that UiShader clips its fragments by, so clips need no scissor and
// rounded ones clip to their corners; the glyph atlas is read filtered (a
// glyph under a turning transform) or at its texels' centres, an instance
// choosing; images of up to PAGED pixels a side (paths' and SVGs'
// rasterizations, gradients, icons, colour glyphs) share atlas pages
// (PAGE pixels square, up to PAGES of them, an image's place in one kept
// while it is drawn), each read clamped to its own texels, so that images
// do not split the draw either. What has a texture of its own (a larger
// image, a browser's, a <Scene>'s GPU texture) is bound in the image slot
// in turn: a draw for each change of it, in the order drawn, painter's
// order kept. Opacity multiplies each
// quad's colour (no group of its own), transforms are each quad's, so
// neither needs a pass; a <Scene>'s passes come before the frame's
// (beforePass). The instance buffer is kept between frames: only the
// instances that changed since the last frame are written (QuadBatch), and
// a steady frame allocates nothing. The UI's pixels are scaled
// to the target's (scale: a Retina display's 2); glyphs are rasterized at the
// scaled size into the GlyphAtlas, its coverage uploaded into a texture's
// red channel where it changed. An image is
// uploaded once (premultiplied, filtered linearly) and again when its
// version changes; forget(image) frees its texture. Under a transform
// (pushTransform) a quad is built in the transform's scaled pixels (its
// scale: the square root of its determinant) and its corners turned into the
// target's by what remains (a rotation, or a skew), so that edges stay
// anti-aliased over a pixel; glyphs are rasterized at the scaled size, and
// read filtered where the transform turns them. A clip pushed under a turning
// transform clips to its bounds. Snapped (snap, the default), what is laid
// out without a transform lies on the target's pixel grid, as a browser's
// layout snaps its boxes: a box's edges, a clip's, an image's origin (its
// size whole pixels), a border's width (at least a pixel), a line of text's
// origin, each rounded to a whole device pixel, so that at a fractional
// scale (a phone's 2.8125) a box or a line of text at rest is crisp and the
// same wherever its points fall, and a hairline is not smeared over two.
// What is under a transform is never snapped: a transform is how things
// move (a mark following the camera, a spring, a tween), and a moving thing
// placed at whole pixels steps from one to the next instead of gliding.
class Renderer implements Canvas {
	public final device:Device;
	public var scale = 1.0;
	// whether unturned, unscaled drawing is put on the pixel grid
	public var snap = true;
	public final atlas:GlyphAtlas;

	final pipeline:Pipeline;
	final atlasTexture:Texture;
	final blank:Texture;
	final linear:Sampler;
	// the shader's texture slots: the atlas's, the image's
	final atlasSlot:Int;
	final imageSlot:Int;
	// the frame's quads, an instance each, in runs: a run's image texture bound (its index)
	final quads = new QuadBatch(STRIDE, 1024, true);
	// the runs' image textures (null: none drawn)
	final runTextures:Array<Null<Texture>> = [];
	var run = 0;
	// (an image by its id: its texture and place; frame: the last one that drew it; one not drawn for EVICT frames is freed)
	final textures = new Map<Int, ImageEntry>();
	// the images' atlas pages
	final pages:Array<ImagePage> = [];
	// other processes' textures by their handles (shared images: helder.story's
	// native preview host's frames), opened once, the last frame that drew each
	final opened = new Map<String, {texture:Texture, frame:Int}>();
	final staleShared:Array<String> = [];
	// the frames begun (begin)
	public var frames(default, null) = 0;
	// the GPU textures drawn this frame (texture: by their negative ids), the passes to record before the frame's (beforePass)
	final gpu = new Map<Int, Texture>();
	final before:Array<Encoder->Void> = [];
	final next:Array<Encoder->Void> = [];
	// (the atlas's changed region as RGBA: grown, kept)
	var region = Bytes.alloc(0);
	// (the ids evicted, kept)
	final stale:Array<Int> = [];
	final stalePaths:Array<Path> = [];

	static inline var EVICT = 300;
	// an image page's size, how many there may be, the largest side of an image put in one
	public static inline var PAGE = 1024;
	public static inline var PAGES = 4;
	public static inline var PAGED = 256;
	// (when the frame began: FrameCounts.uiMs from it to the pass encoded)
	var began = 0.0;
	var beganBytes = 0.0;
	var targetW = 1.0;
	var targetH = 1.0;

	// the state
	var tx = 0.0;
	var ty = 0.0;
	var alpha = 1.0;
	final alphas:Array<Float> = [];
	final clips:Array<Float> = []; // the clips pushed over: x0, y0, x1, y1, the corners' radii (8 each)
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
	// (on the pixel grid: snapped, and no transform)
	var grid = true;
	final transforms:Array<Float> = []; // (9 each)

	static inline var STRIDE = 192; // UiVertex's instance: 48 floats

	// (UiShader's vertex: its corner from a buffer of four, the rest an instance's)
	static function layout():Array<VertexBufferLayout> {
		var a = UiShader.layout[0].attributes;
		return [
			{stride: 8, attributes: [a[0]]},
			{
				stride: STRIDE,
				step: Instance,
				attributes: [for (k in 1...a.length) {location: a[k].location, format: a[k].format, offset: a[k].offset - 8}]
			}
		];
	}

	// (format: a render target's, drawn into in a pass of its own; by default the frame's)
	public function new(device:Device, ?atlas:GlyphAtlas, ?format:TextureFormat) {
		this.device = device;
		this.atlas = atlas == null ? new GlyphAtlas(1024, 1024) : atlas;
		var d = UiShader.pipeline({blend: Premultiplied});
		d.layout = layout();
		if (format != null) d.colorFormat = format;
		pipeline = device.createPipeline(d);
		atlasTexture = device.createTexture({width: this.atlas.width, height: this.atlas.height, format: RGBA8});
		blank = device.createTexture({width: 1, height: 1, format: RGBA8, data: Bytes.ofHex("ffffffff")});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
		atlasSlot = UiShader.textures[0].binding;
		imageSlot = UiShader.textures[1].binding;
	}

	// starts a frame's drawing into a target of width x height pixels
	public function begin(width:Int, height:Int) {
		// (the textures of images no longer drawn: a replaced image, an svg drawn again at another size)
		frames++;
		began = haxe.Timer.stamp();
		#if (target.name == "hxmc")
		beganBytes = hxmc.GcStats.bytesAllocated();
		#end
		if (frames % 60 == 0) {
			stale.resize(0);
			for (id => e in textures)
				if (frames - e.frame > EVICT) stale.push(id);
			for (id in stale) {
				release(textures.get(id));
				textures.remove(id);
			}
			staleShared.resize(0);
			for (h => o in opened)
				if (frames - o.frame > EVICT) staleShared.push(h);
			for (h in staleShared) {
				var t = opened.get(h).texture;
				if (t != blank) device.destroyTexture(t);
				opened.remove(h);
			}
			stalePaths.resize(0);
			for (p => e in paths)
				if (frames - e.frame > EVICT) stalePaths.push(p);
			for (p in stalePaths)
				paths.remove(p);
		}
		targetW = width;
		targetH = height;
		gpu.clear();
		before.resize(0);
		for (f in next)
			before.push(f);
		next.resize(0);
		quads.clear();
		run = 0;
		runTextures.resize(0);
		runTextures.push(null);
		tx = ty = 0;
		alpha = 1;
		alphas.resize(0);
		clips.resize(0);
		transforms.resize(0);
		ma = md = mk = 1;
		mb = mc = me = mf = 0;
		flat = aligned = true;
		grid = snap;
		clipX0 = clipY0 = clipR0 = clipR1 = clipR2 = clipR3 = 0;
		clipX1 = width;
		clipY1 = height;
	}

	// uploads and draws what was drawn since begin, in the pass the encoder
	// is in: one draw, or one more for each change of the image texture bound
	public function end(enc:Encoder) {
		var ending = haxe.Timer.stamp();
		if (atlas.dirtyX1 > atlas.dirtyX0) {
			var x = atlas.dirtyX0, y = atlas.dirtyY0, w = atlas.dirtyX1 - x, h = atlas.dirtyY1 - y;
			// (coverage in the red channel)
			if (region.length < w * h * 4) region = Bytes.alloc(w * h * 4);
			for (r in 0...h) {
				var src = (y + r) * atlas.width + x, dst = r * w * 4;
				for (c in 0...w)
					region.set(dst + c * 4, atlas.pixels.get(src + c));
			}
			device.writeTexture(atlasTexture, region, x, y, w, h);
			atlas.clean();
		}
		FrameCounts.quads += quads.count;
		var uploaded = quads.upload(device), encoding = haxe.Timer.stamp();
		FrameCounts.uploadMs += (encoding - ending) * 1000;
		if (uploaded) {
			enc.setPipeline(pipeline);
			quads.bind(enc);
			enc.setTexture(atlasSlot, atlasTexture, linear);
			for (r in 0...quads.draws()) {
				var t = runTextures[quads.runs[r * 3]];
				if (r == 0 || t != null) enc.setTexture(imageSlot, t == null ? blank : t, linear);
				quads.draw(enc, r);
			}
			FrameCounts.uploaded += quads.uploaded;
		}
		var now = haxe.Timer.stamp();
		FrameCounts.uiMs += (now - began) * 1000;
		FrameCounts.encodeMs += (now - encoding) * 1000;
		#if (target.name == "hxmc")
		FrameCounts.uiBytes += hxmc.GcStats.bytesAllocated() - beganBytes;
		#end
	}

	// (the image texture bound for a quad: the run's, else a new run's)
	inline function bind(t:Texture) {
		var r = runTextures[run];
		if (r == null) runTextures[run] = t;
		else if (r != t) {
			run++;
			runTextures.push(t);
		}
	}

	// f records a pass of its own before the frame's (prepare): what a
	// texture drawn this frame shows, rendered first (a <Scene>'s)
	public function beforePass(f:Encoder->Void)
		before.push(f);

	// a pass recorded before the next frame's, asked outside a paint
	public function nextPass(f:Encoder->Void)
		next.push(f);

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
		release(e);
		textures.remove(img.id);
	}

	// (an image's texture or its place in a page given up)
	function release(e:ImageEntry) {
		if (e.external) return;
		if (e.page < 0) device.destroyTexture(e.texture);
		else pages[e.page].live--;
	}

	// the image's texture, uploaded (premultiplied) when new or changed: an
	// image of up to PAGED pixels a side with its pixels here into a page,
	// any other (a browser's, a large one) a texture of its own
	function texture(img:Image):ImageEntry {
		if (img.shared != null) return sharedTexture(img);
		var e = textures.get(img.id);
		if (e != null) e.frame = frames;
		if (e != null && e.version == img.version) return e;
		// (another size: Image.replace's)
		if (e != null && (e.width != img.width || e.height != img.height)) {
			release(e);
			textures.remove(img.id);
			e = null;
		}
		if (e == null) {
			e = new ImageEntry(img.version, frames, img.width, img.height);
			var browser = img.browser != 0 && !img.hasPixels && device.decodesImages;
			if (!browser && img.width <= PAGED && img.height <= PAGED && allocate(e)) {
				var p = pages[e.page];
				e.texture = p.texture;
				img.premultiplied(pre -> device.writeTexture(p.texture, pre, e.x, e.y, e.width, e.height));
				img.uploaded();
			} else
				// (its pixels dropped after, where they can come back: Image.uploaded)
				e.texture = helder.gfx.ImageTexture.create(device, img, {premultiply: true});
			textures.set(img.id, e);
		} else {
			var t = e.texture;
			// (a browser's image replaced by another, a frame of a worker's: uploaded from its bitmap)
			if (e.page < 0 && img.browser != 0 && !img.hasPixels && device.decodesImages) device.writeTextureImage(t, img.browser);
			else if (e.page >= 0) img.premultiplied(pre -> device.writeTexture(t, pre, e.x, e.y, e.width, e.height));
			else img.premultiplied(pre -> device.writeTexture(t, pre));
			e.version = img.version;
		}
		return e;
	}

	// another process's texture (Image.ofShared: its handle), opened once and
	// drawn as it is (premultiplied, opaque frames), never uploaded; the
	// frames that drew the image counted (Image.drawn: the studio's previews
	// let go of a frame's target once a newer one was drawn)
	function sharedTexture(img:Image):ImageEntry {
		var e = textures.get(img.id);
		if (e == null || !e.external || e.width != img.width || e.height != img.height) {
			if (e != null) release(e);
			e = new ImageEntry(img.version - 1, frames - 1, img.width, img.height);
			e.external = true;
			textures.set(img.id, e);
		}
		if (e.frame != frames) {
			e.frame = frames;
			img.drawn++;
		}
		var o = opened.get(img.shared);
		if (o == null) {
			// (not opened: blank, not tried again)
			o = {texture: device.openShared(img.shared, img.width, img.height) ?? blank, frame: frames};
			opened.set(img.shared, o);
		}
		o.frame = frames;
		e.texture = o.texture;
		e.version = img.version;
		return e;
	}

	// (a place in a page for the entry: in one there is room in, else in one
	// emptied (every image in it evicted or forgotten), else in a new one,
	// up to PAGES; false: none)
	function allocate(e:ImageEntry):Bool {
		for (k in 0...pages.length)
			if (pages[k].allocate(e)) {
				e.page = k;
				return true;
			}
		for (k in 0...pages.length) {
			var p = pages[k];
			if (p.live == 0 && p.used) {
				p.reset();
				if (p.allocate(e)) {
					e.page = k;
					return true;
				}
			}
		}
		if (pages.length >= PAGES) return false;
		var p = new ImagePage(device.createTexture({width: PAGE, height: PAGE, format: RGBA8}));
		pages.push(p);
		if (!p.allocate(e)) return false;
		e.page = pages.length - 1;
		return true;
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
		clips.push(clipX0);
		clips.push(clipY0);
		clips.push(clipX1);
		clips.push(clipY1);
		clips.push(clipR0);
		clips.push(clipR1);
		clips.push(clipR2);
		clips.push(clipR3);
		var k = scale;
		var x0 = (x + tx) * scale, y0 = (y + ty) * scale, x1 = (x + w + tx) * scale, y1 = (y + h + ty) * scale;
		if (grid && snap) {
			x0 = Math.fround(x0);
			y0 = Math.fround(y0);
			x1 = Math.fround(x1);
			y1 = Math.fround(y1);
		}
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
		var n = clips.length - 8, c = clips;
		clipX0 = c[n];
		clipY0 = c[n + 1];
		clipX1 = c[n + 2];
		clipY1 = c[n + 3];
		clipR0 = c[n + 4];
		clipR1 = c[n + 5];
		clipR2 = c[n + 6];
		clipR3 = c[n + 7];
		clips.resize(n);
	}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		transforms.push(ma);
		transforms.push(mb);
		transforms.push(mc);
		transforms.push(md);
		transforms.push(me);
		transforms.push(mf);
		transforms.push(mk);
		transforms.push(flat ? 1 : 0);
		transforms.push(aligned ? 1 : 0);
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
		// (under a transform: where it puts it, not snapped)
		grid = snap && flat;
	}

	public function popTransform() {
		var n = transforms.length - 9, t = transforms;
		ma = t[n];
		mb = t[n + 1];
		mc = t[n + 2];
		md = t[n + 3];
		me = t[n + 4];
		mf = t[n + 5];
		mk = t[n + 6];
		flat = t[n + 7] == 1;
		aligned = t[n + 8] == 1;
		transforms.resize(n);
		grid = snap && flat;
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
		qw0 = side((e == null ? width : e.top) * s);
		qw1 = side((e == null ? width : e.right) * s);
		qw2 = side((e == null ? width : e.bottom) * s);
		qw3 = side((e == null ? width : e.left) * s);
	}

	// (a border's width on the grid: whole pixels, at least one)
	inline function side(w:Float):Float
		return grid && w > 0 ? Math.max(1, Math.fround(w)) : w;

	// (a box's edges on the grid: each rounded, so that boxes side by side stay so)
	inline function edges(x0:Float, y0:Float, x1:Float, y1:Float) {
		if (grid) {
			ex0 = Math.fround(x0);
			ey0 = Math.fround(y0);
			ex1 = Math.fround(x1);
			ey1 = Math.fround(y1);
		} else {
			ex0 = x0;
			ey0 = y0;
			ex1 = x1;
			ey1 = y1;
		}
	}

	var ex0 = 0.0;
	var ey0 = 0.0;
	var ex1 = 0.0;
	var ey1 = 0.0;

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
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
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
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
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
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
	// around it, kept while it is drawn the same way: by path, its paints and
	// the scale, compared without allocating)
	final paths = new haxe.ds.ObjectMap<Path, PathImage>();

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		var b = p.bounds(), s = scale;
		var reach = stroke == null ? 0.0 : stroke.width / 2 * ((stroke.join ?? Miter) == Miter ? Math.max(1, stroke.miterLimit ?? 4) : 1.5);
		var x0 = Math.floor((b.x - reach) * s) - 1, y0 = Math.floor((b.y - reach) * s) - 1;
		var w = Std.int(Math.ceil((b.x + b.width + reach) * s) + 1 - x0), h = Std.int(Math.ceil((b.y + b.height + reach) * s) + 1 - y0);
		if (w <= 0 || h <= 0 || w * h > 4096 * 4096) return;
		var e = paths.get(p);
		if (e == null || !e.same(s, p, fill, stroke)) {
			e = new PathImage(s, p, fill, stroke, p.render(w, h, [s, 0, 0, s, -x0, -y0], fill, stroke), x0 / s, y0 / s);
			paths.set(p, e);
		}
		e.frame = frames;
		image(e.img, e.x, e.y, w / s, h / s, 0, 0, 1, 1, 0);
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		if (w <= 0 || h <= 0) return;
		var s = scale;
		var x0 = (x + tx) * s, y0 = (y + ty) * s, x1 = (x + w + tx) * s, y1 = (y + h + ty) * s;
		// (on the grid: its origin rounded, its size whole pixels, the same wherever it is)
		if (grid) {
			var iw = Math.max(1, Math.fround(x1 - x0)), ih = Math.max(1, Math.fround(y1 - y0));
			x0 = Math.fround(x0);
			y0 = Math.fround(y0);
			x1 = x0 + iw;
			y1 = y0 + ih;
		}
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
		edges((x + tx) * s, (y + ty) * s, (x + w + tx) * s, (y + h + ty) * s);
		var x0 = ex0, y0 = ey0, x1 = ex1, y1 = ey1;
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
			// (the line's origin on the grid: its glyphs placed from a whole pixel)
			var lineX = (ox + lx) * s;
			if (grid) lineX = Math.fround(lineX);
			if (flat && (by - size * 1.5 - reach > clipY1 || by + size + reach < clipY0)) continue;
			for (i in l.glyphStart...l.glyphEnd) {
				var c = t.glyphChar(i);
				if (c == 32 || c == 10 || c == 9 || t.glyphHidden(i)) continue;
				var id = t.glyphId(i), run = t.glyphRun(i);
				var gx = lineX + (t.glyphX(i) + t.glyphOffsetX(i)) * s, gy = by + Math.round(t.glyphOffsetY(i) * s);
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
		// the pen floored to CoreGraphics' step for its ppem, as CoreText places it;
		// the colour's luminance sets font smoothing's dilation)
		var ex = flat ? 0.0 : me - Std.int(me), ey = flat ? 0.0 : mf - Std.int(mf);
		var ix = GlyphAtlas.pixel(gx + ex, size), sub = GlyphAtlas.phase(gx + ex, size);
		var a = atlas.get(f, id, size, sub, oblique, sigma, color & 0xFFFFFF);
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
				r = {image: new Image(w, h, Resize.area(d.rgba, d.width, d.height, w, h)), left: b.left * k, top: Math.round(b.top * k)};
			}
		}
		colorGlyphs.set(key, r);
		return r;
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
	// corners and border sides: qr*, qw*; an instance of UiShader's quad
	function quad(x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, fill:Color, border:Color, mode:Float, blur:Float,
			m:Float, image:Int) {
		// (an image: its texture bound, its place in a page and its texels'
		// bounds there (read clamped to them); a glyph: read filtered where turned)
		var w0 = qw0, w1 = qw1, w2 = qw2, w3 = qw3, filtered = 0;
		if (mode == 2) {
			var e = image < 0 ? null : textures.get(image);
			if (e == null || e.page < 0) {
				bind(e == null ? gpu.get(image) : e.texture);
				w0 = w1 = -1e9;
				w2 = w3 = 1e9;
			} else {
				bind(e.texture);
				var k = 1 / PAGE;
				u0 = (e.x + u0 * e.width) * k;
				u1 = (e.x + u1 * e.width) * k;
				v0 = (e.y + v0 * e.height) * k;
				v1 = (e.y + v1 * e.height) * k;
				w0 = (e.x + 0.5) * k;
				w1 = (e.y + 0.5) * k;
				w2 = (e.x + e.width - 0.5) * k;
				w3 = (e.y + e.height - 0.5) * k;
			}
		} else if (mode == 1) {
			w0 = atlas.width;
			w1 = atlas.height;
			w2 = w3 = 0;
			filtered = aligned ? 0 : 1;
		}
		var o = quads.add(run), b = quads.bytes;
		var fa = fill.a / 255 * alpha, ba = border.a / 255 * alpha;
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		var mu = (u1 - u0) * m / (x1 - x0), mv = (v1 - v0) * m / (y1 - y0);
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		// (the corners in target pixels and clip space: the transform less its scale, exact for none)
		var k = mk, ra = flat ? 1 : ma / k, rb = flat ? 0 : mb / k, rc = flat ? 0 : mc / k, rd = flat ? 1 : md / k, te = flat ? 0 : me, tf = flat ? 0 : mf;
		inline function corner(at:Int, px:Float, py:Float) {
			var X = ra * px + rc * py + te, Y = rb * px + rd * py + tf;
			b.setFloat(at, X / targetW * 2 - 1);
			b.setFloat(at + 4, 1 - Y / targetH * 2);
			b.setFloat(at + 8, X);
			b.setFloat(at + 12, Y);
		}
		corner(o, ax, ay);
		corner(o + 16, bx, ay);
		corner(o + 32, ax, by);
		b.setFloat(o + 48, u0 - mu);
		b.setFloat(o + 52, v0 - mv);
		b.setFloat(o + 56, u1 + mu);
		b.setFloat(o + 60, v1 + mv);
		b.setFloat(o + 64, hx);
		b.setFloat(o + 68, hy);
		b.setFloat(o + 72, hx + m);
		b.setFloat(o + 76, hy + m);
		b.setFloat(o + 80, fill.r / 255 * fa);
		b.setFloat(o + 84, fill.g / 255 * fa);
		b.setFloat(o + 88, fill.b / 255 * fa);
		b.setFloat(o + 92, fa);
		b.setFloat(o + 96, border.r / 255 * ba);
		b.setFloat(o + 100, border.g / 255 * ba);
		b.setFloat(o + 104, border.b / 255 * ba);
		b.setFloat(o + 108, ba);
		b.setFloat(o + 112, qr0);
		b.setFloat(o + 116, qr1);
		b.setFloat(o + 120, qr2);
		b.setFloat(o + 124, qr3);
		b.setFloat(o + 128, w0);
		b.setFloat(o + 132, w1);
		b.setFloat(o + 136, w2);
		b.setFloat(o + 140, w3);
		b.setFloat(o + 144, mode);
		b.setFloat(o + 148, blur);
		b.setFloat(o + 152, filtered);
		b.setFloat(o + 156, 0);
		b.setFloat(o + 160, clipX0);
		b.setFloat(o + 164, clipY0);
		b.setFloat(o + 168, clipX1);
		b.setFloat(o + 172, clipY1);
		b.setFloat(o + 176, clipR0);
		b.setFloat(o + 180, clipR1);
		b.setFloat(o + 184, clipR2);
		b.setFloat(o + 188, clipR3);
	}
}

// (an image's texture: its own (page -1), or a page's, its place x, y in it)
private class ImageEntry {
	public var texture:Null<Texture> = null;
	public var version:Int;
	public var frame:Int;
	public final width:Int;
	public final height:Int;
	public var page = -1;
	// another process's texture (Renderer.opened's): not this entry's to free
	public var external = false;
	public var x = 0;
	public var y = 0;

	public function new(version, frame, width, height) {
		this.version = version;
		this.frame = frame;
		this.width = width;
		this.height = height;
	}
}

// (an atlas page of images: shelves, each a row of images as high as its
// first, filled left to right; live: the images in it; emptied when none are)
private class ImagePage {
	public final texture:Texture;
	public var live = 0;
	public var used = false;
	// (each shelf's top, height and the next x on it)
	final shelves:Array<Int> = [];
	var bottom = 0;

	public function new(texture)
		this.texture = texture;

	public function reset() {
		shelves.resize(0);
		bottom = 0;
		used = false;
	}

	public function allocate(e:ImageEntry):Bool {
		var w = e.width, h = e.height, size = Renderer.PAGE;
		var k = 0;
		while (k < shelves.length) {
			if (shelves[k + 1] >= h && shelves[k + 1] <= h * 2 && shelves[k + 2] + w <= size) {
				place(e, shelves[k + 2], shelves[k]);
				shelves[k + 2] += w;
				return true;
			}
			k += 3;
		}
		if (bottom + h > size) return false;
		shelves.push(bottom);
		shelves.push(h);
		shelves.push(w);
		place(e, 0, bottom);
		bottom += h;
		return true;
	}

	inline function place(e:ImageEntry, x:Int, y:Int) {
		e.x = x;
		e.y = y;
		live++;
		used = true;
	}
}

// (a path's image as Renderer.path drew it, and what it was drawn with)
private class PathImage {
	public final img:Image;
	public final x:Float;
	public final y:Float;
	public var frame = 0;

	final scale:Float;
	final commands:Int;
	final evenOdd:Bool;
	final fill:Null<Paint>;
	final stroke:Null<Stroke>;
	// (the stroke's fields when drawn: a stroke object may be changed and drawn again)
	final width:Float;
	final paint:Null<Paint>;
	final cap:Null<LineCap>;
	final join:Null<LineJoin>;
	final miterLimit:Null<Float>;
	final dashes:Null<Array<Float>>;
	final dashOffset:Null<Float>;

	public function new(scale:Float, p:Path, fill:Null<Paint>, stroke:Null<Stroke>, img:Image, x:Float, y:Float) {
		this.scale = scale;
		commands = p.commands.length;
		evenOdd = p.evenOdd;
		this.fill = fill;
		this.stroke = stroke;
		width = stroke == null ? 0 : stroke.width;
		paint = stroke?.paint;
		cap = stroke?.cap;
		join = stroke?.join;
		miterLimit = stroke?.miterLimit;
		dashes = stroke?.dashes == null ? null : stroke.dashes.copy();
		dashOffset = stroke?.dashOffset;
		this.img = img;
		this.x = x;
		this.y = y;
	}

	public function same(s:Float, p:Path, f:Null<Paint>, st:Null<Stroke>):Bool {
		if (s != scale || p.commands.length != commands || p.evenOdd != evenOdd || !samePaint(f, fill)) return false;
		if (st == null || stroke == null) return st == stroke;
		if (st.width != width || !samePaint(st.paint, paint) || st.cap != cap || st.join != join || st.miterLimit != miterLimit
			|| st.dashOffset != dashOffset) return false;
		var d = st.dashes;
		if (d == null || dashes == null) return d == dashes;
		if (d.length != dashes.length) return false;
		for (k in 0...d.length)
			if (d[k] != dashes[k]) return false;
		return true;
	}

	static function samePaint(a:Null<Paint>, b:Null<Paint>):Bool {
		if (a == null || b == null) return a == b;
		return switch [(a : PaintValue), (b : PaintValue)] {
			case [Solid(x), Solid(y)]: x == y;
			// (another gradient object: the same if it reads the same)
			case [Gradient(x), Gradient(y)]: x == y || Std.string(x) == Std.string(y);
			case _: false;
		}
	}
}
