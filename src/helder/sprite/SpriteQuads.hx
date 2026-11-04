package helder.sprite;

import haxe.io.Bytes;
import helder.sprite.Atlas.AtlasFrame;

// A frame's textured quads, on the CPU: SpriteBatch's vertices (four a
// quad, SpriteShader's SpriteVertex: its position and texel, two floats
// each, and its colour, four bytes; STRIDE bytes) and its runs (the quads
// drawn in order with one texture: a draw each), kept between frames
// (clear empties them, the buffer stays: a steady frame allocates
// nothing). Each quad is a rectangle in its own units (x0, y0, x1, y1) put
// on the target by an affine transform (x' = a x + c y + e, y' = b x + d y
// + f), its texture's u0, v0, u1, v1 over it (or turned a quarter
// clockwise in the texture: an atlas's rotated frame), its colour tinted
// and faded by alpha, premultiplied (a byte each: red, green, blue,
// alpha), and drawn over what is there (alpha blending) or added to it
// (additive: canvas's "lighter", Flash's ADD), both in one pipeline: an
// additive quad's colour has no alpha. 80 bytes a quad (PixiJS's batcher:
// 96; eight floats a vertex before, 128), what a frame writes and uploads.
// (One instance a quad, 52 bytes, was slower: SwiftShader draws instances
// one by one, and small instances waste a GPU's vertex work.)
class SpriteQuads {
	public static inline var STRIDE = 20;

	public var bytes(default, null):Bytes;
	// the quads this frame
	public var count(default, null) = 0;
	// the runs: texture, first quad, quads; three ints each
	public final runs:Array<Int> = [];

	public function new(capacity = 1024) {
		bytes = Bytes.alloc(capacity * 4 * STRIDE);
	}

	public function clear() {
		count = 0;
		runs.resize(0);
	}

	// the number of runs (draws)
	public inline function draws():Int
		return Std.int(runs.length / 3);

	public function quad(texture:Int, x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, a:Float, b:Float, c:Float,
			d:Float, e:Float, f:Float, red:Float, green:Float, blue:Float, alpha:Float, additive:Bool, turned = false) {
		if (alpha <= 0) return;
		if (alpha > 1) alpha = 1;
		var o = count * 4 * STRIDE, out = bytes;
		if (o + 4 * STRIDE > out.length) {
			var n = Bytes.alloc(out.length * 2);
			n.blit(0, out, 0, o);
			bytes = out = n;
		}
		// (white and opaque, most sprites: all ones)
		var rgba = red == 1 && green == 1 && blue == 1 && alpha == 1 && !additive ? -1 : byte(red * alpha) | byte(green * alpha) << 8
			| byte(blue * alpha) << 16 | (additive ? 0 : byte(alpha)) << 24;
		// (the corners: top left, top right, bottom left, bottom right; the
		// top left and the edges from it, the rest from those)
		var px = a * x0 + c * y0 + e, py = b * x0 + d * y0 + f;
		var rx = a * (x1 - x0), ry = b * (x1 - x0), dx = c * (y1 - y0), dy = d * (y1 - y0);
		// (their texels, a turned frame's read a quarter clockwise)
		vertex(out, o, px, py, turned ? u1 : u0, v0, rgba);
		vertex(out, o + STRIDE, px + rx, py + ry, u1, turned ? v1 : v0, rgba);
		vertex(out, o + 2 * STRIDE, px + dx, py + dy, u0, turned ? v0 : v1, rgba);
		vertex(out, o + 3 * STRIDE, px + rx + dx, py + ry + dy, turned ? u0 : u1, v1, rgba);
		var n = runs.length;
		if (n > 0 && runs[n - 3] == texture) runs[n - 1]++ else {
			runs.push(texture);
			runs.push(count);
			runs.push(1);
		}
		count++;
	}

	static inline function vertex(out:Bytes, o:Int, x:Float, y:Float, u:Float, v:Float, rgba:Int) {
		out.setFloat(o, x);
		out.setFloat(o + 4, y);
		out.setFloat(o + 8, u);
		out.setFloat(o + 12, v);
		out.setInt32(o + 16, rgba);
	}

	// (0 to 1 as a byte, rounded; clamped)
	static inline function byte(v:Float):Int
		return v <= 0 ? 0 : v >= 1 ? 255 : Std.int(v * 255 + 0.5);

	// an atlas's frame about its source's centre at x, y, scaled (scaleX,
	// scaleY), then turned by rotation (radians, clockwise on a y-down
	// target), from a texture of tw x th pixels
	public function sprite(texture:Int, tw:Int, th:Int, fr:AtlasFrame, x:Float, y:Float, rotation:Float, scaleX:Float, scaleY:Float, alpha:Float,
			additive = false, red = 1.0, green = 1.0, blue = 1.0) {
		var x0 = fr.trimX - fr.sourceW / 2, y0 = fr.trimY - fr.sourceH / 2;
		var x1 = x0 + fr.w, y1 = y0 + fr.h;
		var cw = fr.rotated ? fr.h : fr.w, ch = fr.rotated ? fr.w : fr.h;
		var u0 = fr.x / tw, v0 = fr.y / th, u1 = (fr.x + cw) / tw, v1 = (fr.y + ch) / th;
		var cs = rotation == 0 ? 1.0 : Math.cos(rotation), sn = rotation == 0 ? 0.0 : Math.sin(rotation);
		quad(texture, x0, y0, x1, y1, u0, v0, u1, v1, cs * scaleX, sn * scaleX, -sn * scaleY, cs * scaleY, x, y, red, green, blue, alpha, additive,
			fr.rotated);
	}

	// a texture's rectangle (sx, sy, sw, sh: its pixels) over x, y, w, h
	public function image(texture:Int, tw:Int, th:Int, sx:Float, sy:Float, sw:Float, sh:Float, x:Float, y:Float, w:Float, h:Float, alpha = 1.0,
			additive = false)
		quad(texture, x, y, x + w, y + h, sx / tw, sy / th, (sx + sw) / tw, (sy + sh) / th, 1, 0, 0, 1, 0, 0, 1, 1, 1, alpha, additive);
}
