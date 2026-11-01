package helder.cli;

import haxe.io.Bytes;
import helder.cli.Manifest;
import helder.image.PngEncoder;

using StringTools;

// Every icon a target needs from the manifest's few (Manifest: its icons,
// PNG, JPEG, WebP or GIF at their sizes, or SVG at any: helder.ui.Svg drawn
// at the size asked): the source picked by purpose (maskable for a
// full-bleed one, any, monochrome), an SVG first, else the smallest raster
// at least as large, else the largest (scaled up at most twice: more is an
// error), scaled (an area's average down, bilinear up, premultiplied) and
// placed on a square canvas (a background colour, the part of it the
// platform keeps). Each made once a build (keyed by source and size).
// What each platform gets (Android, Ios, Page) is theirs; this is the
// pixels, as PNG files (PngEncoder).
class Icons {
	final cfg:AppConfig;
	final root:String;
	final read:String->Bytes;
	final cache = new Map<String, Bytes>();

	// read: a file's bytes by its path from the project's directory (tests: their own)
	public function new(cfg:AppConfig, root:String, ?read:String->Bytes) {
		this.cfg = cfg;
		this.root = root;
		this.read = read ?? (p -> sys.io.File.getBytes(root == "." ? p : '$root/$p'));
	}

	// whether the manifest has an icon of a purpose
	public function has(purpose:String):Bool
		return cfg.icons != null && Lambda.exists(cfg.icons, i -> i.purpose.contains(purpose) && usable(i));

	static function usable(i:IconSpec):Bool
		return !i.src.toLowerCase().endsWith(".ico") && i.type != "image/x-icon" && i.type != "image/vnd.microsoft.icon";

	static function isSvg(i:IconSpec):Bool
		return i.type == "image/svg+xml" || i.src.toLowerCase().endsWith(".svg");

	// the icon of the first purpose there is one of, for px pixels (null: none)
	public function pick(purposes:Array<String>, px:Int):Null<IconSpec> {
		for (p in purposes) {
			var all = cfg.icons == null ? [] : [for (i in cfg.icons) if (i.purpose.contains(p) && usable(i)) i];
			if (all.length == 0) continue;
			for (i in all) if (isSvg(i)) return i;
			var best:Null<IconSpec> = null, largest:Null<IconSpec> = null;
			function size(i:IconSpec):Int {
				var s = 0;
				if (i.sizes != null) for (v in i.sizes) if (v > s) s = v;
				return s;
			}
			for (i in all) {
				var s = size(i);
				if (s >= px && (best == null || s < size(best))) best = i;
				if (largest == null || s > size(largest)) largest = i;
			}
			return best ?? largest;
		}
		return null;
	}

	// an icon's pixels at px x px, RGBA (what: the use, for the messages)
	public function pixels(i:IconSpec, px:Int, what:String):Bytes {
		var key = i.src + "@" + px;
		if (cache.exists(key)) return cache.get(key);
		var at = cfg.icons == null ? -1 : cfg.icons.indexOf(i);
		var name = at >= 0 ? '${cfg.source ?? Manifest.FILE}: icons[$at] (${i.src})' : '${cfg.source ?? Manifest.FILE}: ${i.src}';
		var bytes = try read(i.src) catch (e:Dynamic) throw '$name: no such file';
		var out = isSvg(i) ? {
			var svg = try helder.ui.Svg.parse(bytes.toString()) catch (e:Dynamic) throw '$name: not an SVG ($e)';
			svg.render(px, px).pixels;
		} : {
			var img = try helder.image.Image.decode(bytes) catch (e:Dynamic) throw '$name: not an image ($e)';
			if (img.width != img.height) throw '$name: ${img.width}x${img.height}: an icon is square';
			if (i.sizes != null && !i.sizes.contains(img.width)) throw '$name: ${img.width}x${img.height}, but its sizes say ${[for (s in i.sizes) '${s}x$s'].join(" ")}';
			if (img.width * 2 < px) throw '$name: ${img.width}x${img.width} is too small for $what (${px}x$px): give one of ${px}x$px or more, or an SVG';
			scale(img.pixels, img.width, px);
		}
		cache.set(key, out);
		return out;
	}

	// a square canvas of px with a background (null: transparent) and the
	// icon of the purposes centred on it at fraction of its side
	public function canvas(purposes:Array<String>, px:Int, fraction:Float, background:Null<Int>, what:String, ?src:String):Null<Bytes> {
		var i = src != null ? ({src: src, sizes: null, purpose: ["any"]} : IconSpec) : pick(purposes, Math.round(px * fraction));
		if (i == null) return null;
		var c = fill(px, background);
		var n = Math.round(px * fraction);
		over(c, px, pixels(i, n, what), n, (px - n) >> 1, (px - n) >> 1);
		return c;
	}

	// as a PNG file
	public function png(purposes:Array<String>, px:Int, fraction:Float, background:Null<Int>, what:String, ?src:String):Null<Bytes> {
		var c = canvas(purposes, px, fraction, background, what, src);
		return c == null ? null : PngEncoder.encode(c, px, px);
	}

	public static function fill(px:Int, color:Null<Int>):Bytes {
		var b = Bytes.alloc(px * px * 4);
		if (color != null) {
			var r = (color >> 16) & 0xFF, g = (color >> 8) & 0xFF, bl = color & 0xFF, a = (color >>> 24) & 0xFF;
			for (k in 0...px * px) {
				b.set(4 * k, r);
				b.set(4 * k + 1, g);
				b.set(4 * k + 2, bl);
				b.set(4 * k + 3, a);
			}
		}
		return b;
	}

	// src (n x n, straight alpha) over the canvas (cw wide) at x, y
	public static function over(c:Bytes, cw:Int, src:Bytes, n:Int, x:Int, y:Int) {
		for (sy in 0...n) {
			var dy = y + sy;
			if (dy < 0 || dy >= cw) continue;
			for (sx in 0...n) {
				var dx = x + sx;
				if (dx < 0 || dx >= cw) continue;
				var s = 4 * (sy * n + sx), d = 4 * (dy * cw + dx);
				var sa = src.get(s + 3) / 255;
				if (sa == 0) continue;
				var da = c.get(d + 3) / 255, oa = sa + da * (1 - sa);
				for (k in 0...3)
					c.set(d + k, Math.round((src.get(s + k) * sa + c.get(d + k) * da * (1 - sa)) / oa));
				c.set(d + 3, Math.round(oa * 255));
			}
		}
	}

	// a square image of side n scaled to side m: each output pixel the
	// average of the source's area under it (down), or bilinear (up),
	// premultiplied
	public static function scale(rgba:Bytes, n:Int, m:Int):Bytes {
		if (n == m) return rgba;
		var out = Bytes.alloc(m * m * 4);
		inline function px(x:Int, y:Int, k:Int):Float {
			var p = 4 * (y * n + x), a = rgba.get(p + 3);
			return k == 3 ? a : rgba.get(p + k) * a / 255;
		}
		var acc = [0.0, 0, 0, 0];
		for (y in 0...m)
			for (x in 0...m) {
				for (k in 0...4)
					acc[k] = 0;
				if (m < n) {
					var x0 = x * n / m, x1 = (x + 1) * n / m, y0 = y * n / m, y1 = (y + 1) * n / m;
					var total = 0.0;
					for (sy in Math.floor(y0)...Math.ceil(y1)) {
						var wy = Math.min(sy + 1, y1) - Math.max(sy, y0);
						for (sx in Math.floor(x0)...Math.ceil(x1)) {
							var w = wy * (Math.min(sx + 1, x1) - Math.max(sx, x0));
							for (k in 0...4)
								acc[k] += w * px(sx, sy, k);
							total += w;
						}
					}
					for (k in 0...4)
						acc[k] /= total;
				} else {
					var fx = (x + 0.5) * n / m - 0.5, fy = (y + 0.5) * n / m - 0.5;
					if (fx < 0) fx = 0;
					if (fy < 0) fy = 0;
					var ix = Std.int(fx), iy = Std.int(fy), tx = fx - ix, ty = fy - iy;
					var jx = ix + 1 < n ? ix + 1 : ix, jy = iy + 1 < n ? iy + 1 : iy;
					for (k in 0...4)
						acc[k] = (px(ix, iy, k) * (1 - tx) + px(jx, iy, k) * tx) * (1 - ty) + (px(ix, jy, k) * (1 - tx) + px(jx, jy, k) * tx) * ty;
				}
				var o = 4 * (y * m + x), a = acc[3];
				for (k in 0...3)
					out.set(o + k, a <= 0 ? 0 : Math.round(Math.min(255, acc[k] * 255 / a)));
				out.set(o + 3, Math.round(a));
			}
		return out;
	}

	// ---- what each platform gets

	// the colour behind an icon that has none (an adaptive icon's background, iOS's opaque one)
	public function background():Int
		return cfg.background ?? cfg.theme ?? 0xFFFFFFFF;

	// Android: the adaptive icon's layers, 108 dp at xxxhdpi (432 px):
	// a maskable icon's safe zone (its middle 80%) on the layer's (66 dp),
	// an icon of any purpose within that zone (its inscribed square); the
	// monochrome layer (Android 13's themed icons) likewise. null: no icon
	public static inline var ANDROID_LAYER = 432;
	public static inline var ANDROID_SPLASH = 1152;

	public function androidForeground():Null<Bytes>
		return has("maskable") ? png(["maskable"], ANDROID_LAYER, 66 / 108 / 0.8, null, "Android's adaptive icon") : png(["any"], ANDROID_LAYER,
			66 / 108 * 0.75, null, "Android's adaptive icon");

	public function androidMonochrome():Null<Bytes>
		return has("monochrome") ? png(["monochrome"], ANDROID_LAYER, 66 / 108 / 0.8, null, "Android's themed icon") : null;

	// Android 12's splash icon (windowSplashScreenAnimatedIcon): 288 dp at
	// xxxhdpi, the image within the 192 dp circle the system keeps (its
	// inscribed square)
	public function androidSplash(src:String):Bytes
		return png([], ANDROID_SPLASH, 192 / 288 * 0.7071, null, "Android's splash icon", src);

	// iOS: the app icon, opaque (the home screen rounds it): full bleed, a
	// maskable one first, else one of any purpose on the background
	public function ios(px:Int):Null<Bytes>
		return png(["maskable", "any"], px, 1, background(), "iOS's app icon");

	// a launch screen image of side px: the splash image (else the icon)
	// at content px in the middle of the splash's background
	public function launch(px:Int, content:Int, src:Null<String>, background:Null<Int>):Null<Bytes> {
		var c = fill(px, background);
		var i = src != null ? ({src: src, sizes: null, purpose: ["any"]} : IconSpec) : pick(["any", "maskable"], content);
		if (i == null && background == null) return null;
		if (i != null) over(c, px, pixels(i, content, "the launch screen"), content, (px - content) >> 1, (px - content) >> 1);
		return PngEncoder.encode(c, px, px);
	}
}
