package helder.canvas;

import haxe.ds.Vector;
import haxe.io.Bytes;
import helder.canvas.Blend.Blender;
import helder.canvas.Paint.Rgba;
import helder.canvas.Paint.Shader;

// A 2D canvas drawn on the CPU: paths filled by non-zero or even-odd,
// stroked (Stroke: width, joins, caps, dashes, as outlines), images,
// with paints (colours, gradients, patterns), opacity and blend modes;
// a transform stack, clips (each a coverage mask), layers (saveLayer:
// drawn apart, then composited with an opacity, a blend mode, a mask and a
// filter: Filter's blur, drop shadow, colour matrices).
// Coverage is analytic (Raster: each pixel's exact area), into
// premultiplied RGBA8 (bitmap), so its pixels are the same on every
// machine. Its buffers are made with it, or once for the deepest save:
// drawing allocates nothing.
//
//   var c = new Canvas(200, 100);
//   var p = new Path();
//   p.roundRect(10, 10, 180, 80, 12);
//   c.fill(p, Paint.solid(0xFF3366CC));
//   File.saveBytes("out.png", c.toPng());
final class Canvas implements Painter {
	public var width(default, null):Int;
	public var height(default, null):Int;
	// the canvas's own pixels (a layer's go elsewhere until it is restored)
	public final bitmap:Bitmap;

	final raster:Raster;
	final stroker = new Stroker();
	// a row's coverage, a span's shaded colours
	final cov:Bytes;
	final span:Vector<Float>;
	final src = new Rgba();
	final dst = new Rgba();
	final inverse = new Matrix();
	final scratch = new Path();
	var image:Null<Pattern> = null;

	final states:Array<State> = [];
	var depth = 0;
	var state:State;
	// the pixels drawn into: the bitmap's, or the innermost layer's
	var target:Bytes;

	// curves flattened within this many device pixels
	public var tolerance = 0.1;

	public function new(width:Int, height:Int) {
		if (width < 1) width = 1;
		if (height < 1) height = 1;
		this.width = width;
		this.height = height;
		bitmap = new Bitmap(width, height);
		target = bitmap.pixels;
		raster = new Raster(width, height);
		cov = Bytes.alloc(width + 2);
		span = new Vector(width * 4);
		state = new State();
		state.reset(width, height);
		states.push(state);
	}

	// the current transform (user units to device pixels): changed in place
	public var matrix(get, never):Matrix;

	inline function get_matrix()
		return state.matrix;

	public function translate(x:Float, y:Float)
		state.matrix.translate(x, y);

	public function scale(x:Float, y:Float)
		state.matrix.scale(x, y);

	public function rotate(angle:Float)
		state.matrix.rotate(angle);

	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		state.matrix.transform(a, b, c, d, e, f);

	public function setTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		state.matrix.set(a, b, c, d, e, f);

	public function resetTransform()
		state.matrix.identity();

	public var saveCount(get, never):Int;

	inline function get_saveCount()
		return depth;

	// the transform and the clip kept, to come back to with restore()
	public function save() {
		depth++;
		if (states.length <= depth) states.push(new State());
		var s = states[depth];
		s.inherit(state);
		state = s;
	}

	// what follows drawn apart, then composited with alpha, blend (null:
	// source-over) and mask (a coverage of the canvas's size, or null) at
	// restore(), its pixels through filter first; a save as well
	public function saveLayer(alpha = 1.0, ?blend:Blender, ?mask:Mask, ?filter:Filter) {
		save();
		var s = state;
		s.layer = true;
		s.layerAlpha = alpha;
		s.layerBlend = blend;
		s.layerMask = mask;
		s.layerFilter = filter;
		s.under = target;
		if (s.pixels == null || s.pixels.length != width * height * 4) s.pixels = Bytes.alloc(width * height * 4);
		s.pixels.fill(0, width * height * 4, 0);
		target = s.pixels;
	}

	public function restore() {
		if (depth == 0) return;
		var s = state;
		depth--;
		state = states[depth];
		if (s.layer) {
			target = s.under;
			s.layer = false;
			// (its filter on its pixels first: a blur, a shadow, a colour matrix)
			if (s.layerFilter != null) s.layerFilter.apply(new Bitmap(width, height, s.pixels));
			compositeLayer(s);
			s.layerFilter = null;
			s.layerMask = null;
			s.layerBlend = null;
			s.under = null;
		}
	}

	public function restoreToCount(count:Int) {
		while (depth > count)
			restore();
	}

	// the clip narrowed to the path's inside (by the transform now)
	public function clip(path:Path, evenOdd = false) {
		raster.reset();
		path.flatten(raster, state.matrix, tolerance);
		var mask = state.ownMask(depth, width, height);
		// (rows and columns outside the path: out of the clip)
		var x0 = state.clipX0, x1 = state.clipX1, y0 = state.clipY0, y1 = state.clipY1;
		var ry0 = raster.y0, ry1 = raster.y1, rx0 = raster.x0, rx1 = raster.x1;
		for (y in y0...y1) {
			var row = y * width;
			if (y < ry0 || y >= ry1 || raster.isEmpty()) {
				mask.fill(row + x0, x1 - x0, 0);
				continue;
			}
			raster.row(y, cov, evenOdd);
			for (x in x0...x1) {
				var c = x < rx0 || x >= rx1 ? 0 : cov.get(x);
				var m = mask.get(row + x);
				mask.set(row + x, c == 255 ? m : c == 0 ? 0 : div255(m * c));
			}
		}
		raster.discard();
		var nx0 = rx0 > x0 ? rx0 : x0, nx1 = rx1 < x1 ? rx1 : x1, ny0 = ry0 > y0 ? ry0 : y0, ny1 = ry1 < y1 ? ry1 : y1;
		if (nx1 < nx0) nx1 = nx0;
		if (ny1 < ny0) ny1 = ny0;
		state.clipX0 = nx0;
		state.clipX1 = nx1;
		state.clipY0 = ny0;
		state.clipY1 = ny1;
	}

	public function clipRect(x:Float, y:Float, w:Float, h:Float) {
		scratch.clear();
		scratch.rect(x, y, w, h);
		clip(scratch);
	}

	// the path's inside painted
	public function fill(path:Path, paint:Paint, evenOdd = false) {
		raster.reset();
		path.flatten(raster, state.matrix, tolerance);
		draw(paint, evenOdd);
	}

	// the path's stroke painted (its outline through the transform: a
	// non-uniform scale makes it wider one way)
	public function stroke(path:Path, style:Stroke, paint:Paint) {
		if (!(style.width > 0) || !Math.isFinite(style.width)) return;
		raster.reset();
		stroker.stroke(path, style, state.matrix, raster, tolerance);
		draw(paint, false);
	}

	public function fillRect(x:Float, y:Float, w:Float, h:Float, paint:Paint) {
		scratch.clear();
		scratch.rect(x, y, w, h);
		fill(scratch, paint);
	}

	// the rectangle made transparent (through the transform and the clip)
	public function clearRect(x:Float, y:Float, w:Float, h:Float) {
		scratch.clear();
		scratch.rect(x, y, w, h);
		raster.reset();
		scratch.flatten(raster, state.matrix, tolerance);
		erase.blend = Blend.destinationOut;
		draw(erase, false);
	}

	final erase = new Paint(0xFF000000);

	// everything transparent, the clip and transform aside
	public function clear(color = 0) {
		var p = premultiplied(color);
		for (i in 0...width * height)
			target.setInt32(i * 4, p);
	}

	// a bitmap's region (sx, sy, sw, sh) drawn into the rectangle (dx, dy,
	// dw, dh), through the transform; smooth: bilinear, else the nearest
	// pixel; paint's alpha and blend apply (its colour does not)
	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth = true) {
		if (sw == 0 || sh == 0 || dw == 0 || dh == 0) return;
		// (a source rectangle past the image: cut, the destination with it, as Canvas 2D's)
		if (sw < 0) {
			sx += sw;
			sw = -sw;
		}
		if (sh < 0) {
			sy += sh;
			sh = -sh;
		}
		if (dw < 0) {
			dx += dw;
			dw = -dw;
		}
		if (dh < 0) {
			dy += dh;
			dh = -dh;
		}
		var kx = dw / sw, ky = dh / sh;
		if (sx < 0) {
			dx -= sx * kx;
			dw += sx * kx;
			sw += sx;
			sx = 0;
		}
		if (sy < 0) {
			dy -= sy * ky;
			dh += sy * ky;
			sh += sy;
			sy = 0;
		}
		if (sx + sw > img.width) {
			dw -= (sx + sw - img.width) * kx;
			sw = img.width - sx;
		}
		if (sy + sh > img.height) {
			dh -= (sy + sh - img.height) * ky;
			sh = img.height - sy;
		}
		if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
		var pat = image;
		if (pat == null) image = pat = new Pattern(img, false, false);
		pat.bitmap = img;
		pat.smooth = smooth;
		pat.clamp = true;
		pat.sx0 = sx;
		pat.sy0 = sy;
		pat.sx1 = sx + sw;
		pat.sy1 = sy + sh;
		pat.matrix.set(kx, 0, 0, ky, dx - sx * kx, dy - sy * ky);
		var saved = paint.shader;
		paint.shader = pat;
		scratch.clear();
		scratch.rect(dx, dy, dw, dh);
		raster.reset();
		scratch.flatten(raster, state.matrix, tolerance);
		draw(paint, false);
		paint.shader = saved;
	}

	// the coverage in the rasterizer painted with paint
	function draw(paint:Paint, evenOdd:Bool) {
		var s = state, blend = paint.blend;
		var unbounded = blend != null && blend.unbounded;
		var alpha = paint.alpha;
		if (!(alpha > 0) && !unbounded) {
			raster.discard();
			return;
		}
		if (alpha > 1) alpha = 1;
		var shader = paint.shader;
		if (shader != null) {
			if (!s.matrix.invertInto(inverse) || !shader.begin(inverse)) {
				if (!unbounded) {
					raster.discard();
					return;
				}
				shader = null;
				alpha = 0;
			}
		}
		var c = paint.color, ca = ((c >>> 24) & 255) / 255;
		var sr = ((c >> 16) & 255) / 255 * ca, sg = ((c >> 8) & 255) / 255 * ca, sb = (c & 255) / 255 * ca, sa = ca;
		var cx0 = s.clipX0, cx1 = s.clipX1, cy0 = s.clipY0, cy1 = s.clipY1;
		var mask = s.mask;
		var ry0 = raster.y0, ry1 = raster.y1, rx0 = raster.x0, rx1 = raster.x1, empty = raster.isEmpty();
		var ya = unbounded ? cy0 : (ry0 > cy0 ? ry0 : cy0), yb = unbounded ? cy1 : (ry1 < cy1 ? ry1 : cy1);
		var xa = unbounded ? cx0 : (rx0 > cx0 ? rx0 : cx0), xb = unbounded ? cx1 : (rx1 < cx1 ? rx1 : cx1);
		if (xb <= xa) {
			raster.discard();
			return;
		}
		for (y in ya...yb) {
			var inRaster = !empty && y >= ry0 && y < ry1;
			if (inRaster) raster.row(y, cov, evenOdd);
			if (unbounded) {
				if (!inRaster) cov.fill(xa, xb - xa, 0) else {
					if (rx0 > xa) cov.fill(xa, rx0 - xa, 0);
					if (rx1 < xb) cov.fill(rx1, xb - rx1, 0);
				}
			} else if (!inRaster) continue;
			var row = y * width;
			// (a colour over: integers, a run of whole coverage of an opaque one stored as it is)
			if (shader == null && blend == null) {
				solidSpan(row, xa, xb, mask, alpha, c);
				continue;
			}
			if (shader != null) shader.shade(xa, y, xb - xa, span);
			for (x in xa...xb) {
				var k = cov.get(x);
				var m = mask == null ? 255 : mask.get(row + x);
				if (!unbounded && (k == 0 || m == 0)) continue;
				var o = (row + x) * 4;
				var f = unbounded ? k / 255 * alpha : k * m / 65025 * alpha;
				if (shader != null) {
					var so = (x - xa) * 4;
					src.r = span[so] * f;
					src.g = span[so + 1] * f;
					src.b = span[so + 2] * f;
					src.a = span[so + 3] * f;
				} else {
					src.r = sr * f;
					src.g = sg * f;
					src.b = sb * f;
					src.a = sa * f;
				}
				if (blend == null) {
					if (src.a <= 0) continue;
					var inv = 1 - src.a;
					target.set(o, ch(src.r + target.get(o) / 255 * inv));
					target.set(o + 1, ch(src.g + target.get(o + 1) / 255 * inv));
					target.set(o + 2, ch(src.b + target.get(o + 2) / 255 * inv));
					target.set(o + 3, ch(src.a + target.get(o + 3) / 255 * inv));
					continue;
				}
				var d0 = target.get(o) / 255, d1 = target.get(o + 1) / 255, d2 = target.get(o + 2) / 255, d3 = target.get(o + 3) / 255;
				dst.r = d0;
				dst.g = d1;
				dst.b = d2;
				dst.a = d3;
				blend.blend(src, dst);
				if (unbounded && m < 255) {
					var t = m / 255;
					dst.r = d0 + (dst.r - d0) * t;
					dst.g = d1 + (dst.g - d1) * t;
					dst.b = d2 + (dst.b - d2) * t;
					dst.a = d3 + (dst.a - d3) * t;
				}
				var a = clamp01(dst.a);
				target.set(o, ch(Math.min(dst.r, a)));
				target.set(o + 1, ch(Math.min(dst.g, a)));
				target.set(o + 2, ch(Math.min(dst.b, a)));
				target.set(o + 3, ch(a));
			}
		}
		raster.discard();
	}

	// a colour (0xAARRGGBB) source-over across a row's span of coverage, in
	// integers: premultiplied by its coverage (and the clip's, and alpha)
	// in 0 to 255, d = s + d (255 - sa) / 255; where all of it covers and
	// it is opaque, its pixel stored as it is
	function solidSpan(row:Int, xa:Int, xb:Int, mask:Null<Bytes>, alpha:Float, c:Int) {
		var a = Std.int(((c >>> 24) & 255) * alpha + 0.5);
		if (a <= 0) return;
		var r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
		var whole = a == 255 ? (r | (g << 8) | (b << 16) | (255 << 24)) : 0;
		var t = target;
		for (x in xa...xb) {
			var k = cov.get(x);
			if (k == 0) continue;
			if (mask != null) {
				var m = mask.get(row + x);
				if (m == 0) continue;
				if (m < 255) k = div255(k * m);
			}
			var o = (row + x) * 4;
			if (k == 255 && a == 255) {
				t.setInt32(o, whole);
				continue;
			}
			// (the source's alpha with its coverage, its colour premultiplied by it)
			var sa = div255(a * k);
			if (sa == 0) continue;
			var inv = 255 - sa;
			t.set(o, div255(r * sa) + div255(t.get(o) * inv));
			t.set(o + 1, div255(g * sa) + div255(t.get(o + 1) * inv));
			t.set(o + 2, div255(b * sa) + div255(t.get(o + 2) * inv));
			t.set(o + 3, sa + div255(t.get(o + 3) * inv));
		}
	}

	// a layer's pixels onto those under it, with its alpha, blend and mask,
	// within the clip it was made in
	function compositeLayer(l:State) {
		var s = state, blend = l.layerBlend, unbounded = blend != null && blend.unbounded;
		var alpha = l.layerAlpha;
		if (alpha > 1) alpha = 1;
		if (!(alpha > 0)) alpha = 0;
		var mask = s.mask, lm = l.layerMask, px = l.pixels;
		for (y in s.clipY0...s.clipY1) {
			var row = y * width;
			for (x in s.clipX0...s.clipX1) {
				var i = row + x, o = i * 4;
				var m = mask == null ? 255 : mask.get(i);
				if (m == 0) continue;
				var f = alpha * (lm == null ? 1 : lm.coverage.get(i) / 255);
				var la = px.get(o + 3);
				if (!unbounded && (la == 0 || f == 0)) continue;
				if (!unbounded) f *= m / 255;
				src.r = px.get(o) / 255 * f;
				src.g = px.get(o + 1) / 255 * f;
				src.b = px.get(o + 2) / 255 * f;
				src.a = la / 255 * f;
				if (blend == null) {
					var inv = 1 - src.a;
					target.set(o, ch(src.r + target.get(o) / 255 * inv));
					target.set(o + 1, ch(src.g + target.get(o + 1) / 255 * inv));
					target.set(o + 2, ch(src.b + target.get(o + 2) / 255 * inv));
					target.set(o + 3, ch(src.a + target.get(o + 3) / 255 * inv));
					continue;
				}
				var d0 = target.get(o) / 255, d1 = target.get(o + 1) / 255, d2 = target.get(o + 2) / 255, d3 = target.get(o + 3) / 255;
				dst.r = d0;
				dst.g = d1;
				dst.b = d2;
				dst.a = d3;
				blend.blend(src, dst);
				if (unbounded && m < 255) {
					var t = m / 255;
					dst.r = d0 + (dst.r - d0) * t;
					dst.g = d1 + (dst.g - d1) * t;
					dst.b = d2 + (dst.b - d2) * t;
					dst.a = d3 + (dst.a - d3) * t;
				}
				var a = clamp01(dst.a);
				target.set(o, ch(Math.min(dst.r, a)));
				target.set(o + 1, ch(Math.min(dst.g, a)));
				target.set(o + 2, ch(Math.min(dst.b, a)));
				target.set(o + 3, ch(a));
			}
		}
	}

	// the pixels as straight RGBA (a region: getImageData's)
	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int)
		bitmap.readStraight(out, x, y, w, h);

	// straight RGBA written in, as they are (putImageData's: no blending, no clip)
	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1)
		bitmap.writeStraight(rgba, x, y, w, h, srcStride);

	// its own bitmap (drawn into still)
	public function snapshot():Bitmap
		return bitmap;

	public function offscreen(width:Int, height:Int):Painter
		return new Canvas(width, height);

	// PNG (helder.image's encoder)
	public function toPng():Bytes
		return helder.image.PngEncoder.encode(bitmap.straight(), width, height);

	// JPEG at quality 1 to 100 (helder.image's baseline encoder), over background (0xRRGGBB)
	public function toJpeg(quality = 92, background = 0x000000):Bytes {
		var rgba = bitmap.straight();
		return helder.image.JpegEncoder.encode(rgba, width, height, quality, background);
	}

	static inline function ch(v:Float):Int
		return v <= 0 ? 0 : v >= 1 ? 255 : Std.int(v * 255 + 0.5);

	static inline function clamp01(v:Float):Float
		return v < 0 ? 0 : v > 1 ? 1 : v;

	static inline function div255(v:Int):Int
		return (v + 128 + ((v + 128) >> 8)) >> 8;

	// 0xAARRGGBB as premultiplied RGBA8's bytes in memory order (an Int32, little-endian)
	static function premultiplied(c:Int):Int {
		var a = (c >>> 24) & 255;
		var r = div255(((c >> 16) & 255) * a), g = div255(((c >> 8) & 255) * a), b = div255((c & 255) * a);
		return r | (g << 8) | (b << 16) | (a << 24);
	}
}

// A save's transform and clip (its mask, shared with the save's parent
// until it clips, then its own: one buffer per depth, kept), a layer's
// pixels and how they composite
@:allow(helder.canvas.Canvas)
private final class State {
	public final matrix = new Matrix();
	public var mask:Null<Bytes> = null;
	var own:Null<Bytes> = null;
	var owned = false;
	public var clipX0 = 0;
	public var clipY0 = 0;
	public var clipX1 = 0;
	public var clipY1 = 0;

	public var layer = false;
	public var layerAlpha = 1.0;
	public var layerBlend:Null<Blender> = null;
	public var layerMask:Null<Mask> = null;
	public var layerFilter:Null<Filter> = null;
	public var pixels:Null<Bytes> = null;
	public var under:Null<Bytes> = null;

	public function new() {}

	public function reset(w:Int, h:Int) {
		matrix.identity();
		mask = null;
		owned = false;
		clipX0 = clipY0 = 0;
		clipX1 = w;
		clipY1 = h;
	}

	public function inherit(p:State) {
		matrix.copyFrom(p.matrix);
		mask = p.mask;
		owned = false;
		clipX0 = p.clipX0;
		clipY0 = p.clipY0;
		clipX1 = p.clipX1;
		clipY1 = p.clipY1;
		layer = false;
	}

	// this depth's mask to narrow: the parent's copied (or all in) the first time
	public function ownMask(depth:Int, w:Int, h:Int):Bytes {
		if (owned) return mask;
		if (own == null) own = Bytes.alloc(w * h);
		if (mask == null) own.fill(0, w * h, 255) else own.blit(0, mask, 0, w * h);
		mask = own;
		owned = true;
		return own;
	}
}
