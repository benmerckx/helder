package helder.text;

import haxe.io.Bytes;
import haxe.ds.Vector;

// Which engine shapes and rasterises: helder's own (the same glyphs and
// pixels on every machine: what tests, stories and store screenshots use,
// so that goldens do not vary by OS) or the platform's (SYSTEM: HarfBuzz
// and FreeType on Linux, DirectWrite on Windows, Core Text on macOS) for
// what helder's does not do: the scripts that need reordering and
// conjuncts (Indic, Khmer, Myanmar, Tibetan, Sinhala and the like) and
// the glyphs' rasters. Line layout, carets, selection and drawing stay
// TextLayout's and the atlas's either way.
//
// Per app: Shaping.engine (default SYSTEM; HELDER_TEXT_ENGINE=helder, or
// the define helder.text.engine=helder, which `helder test` sets: HELDER).
// Per font: FontFile.engine (DEFAULT follows the app's).
//
// helder's engine draws glyphs as macOS's CoreText does (GlyphPipeline),
// with font smoothing or without (FontSmoothing): per app Shaping.smoothing
// (HELDER_FONT_SMOOTHING=on|off, or the define helder.text.smoothing; On by
// default on every OS), per window its atlas's (GlyphAtlas.smoothing).
class Shaping {
	public static inline var DEFAULT = 0;
	public static inline var HELDER = 1;
	public static inline var SYSTEM = 2;

	public static var engine(get, set):Int;
	static var chosen = -1;

	static function get_engine():Int {
		if (chosen < 0) {
			#if (helder.text.engine == "helder")
			chosen = HELDER;
			#else
			var e = Sys.getEnv("HELDER_TEXT_ENGINE");
			chosen = e != null && e.toLowerCase() == "helder" ? HELDER : SYSTEM;
			#end
		}
		return chosen;
	}

	static function set_engine(v:Int):Int
		return chosen = v == DEFAULT ? SYSTEM : v;

	public static var smoothing(get, set):FontSmoothing;
	static var smoothingChosen:Null<FontSmoothing> = null;

	static function get_smoothing():FontSmoothing {
		if (smoothingChosen == null) {
			#if (helder.text.smoothing == "off")
			smoothingChosen = Off;
			#else
			var e = FontSmoothing.parse(Sys.getEnv("HELDER_FONT_SMOOTHING"));
			smoothingChosen = e == null ? On : e;
			#end
		}
		return smoothingChosen;
	}

	static function set_smoothing(v:FontSmoothing):FontSmoothing
		return smoothingChosen = v;

	// the platform's back end for a face (null: helder's own engine for it)
	public static function backendFor(f:FontFile):Null<TextBackend> {
		var e = f.engine == DEFAULT ? engine : f.engine;
		if (e != SYSTEM || f.varied) return null;
		return backend();
	}

	static var tried = false;
	static var platform:Null<TextBackend> = null;

	// this platform's back end (null: none here, or its libraries absent)
	public static function backend():Null<TextBackend> {
		if (tried) return platform;
		tried = true;
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		// (constant conditions, Platform.os() and Platform.target() known when compiling: no other system's links)
		if (hxmc.Platform.apple() == 0) {
			if (hxmc.Platform.os() == 0 && hxmc.Platform.target() < 9) platform = helder.text.linux.LinuxText.create();
			else if (hxmc.Platform.os() == 2) platform = helder.text.windows.DirectWrite.create();
			else if (hxmc.Platform.os() == 1) platform = helder.text.mac.CoreText.create();
		}
		#end
		return platform;
	}

	// whether a character's script needs the platform's shaper (reordering,
	// conjuncts, split vowels: what helder's engine does not do)
	public static function complex(c:Int):Bool
		return c >= 0x900 && c <= 0xDFF // (Devanagari to Sinhala: the Indic scripts)
			|| c >= 0xF00 && c <= 0x109F // (Tibetan, Myanmar)
			|| c >= 0x1700 && c <= 0x17FF // (Philippine scripts, Khmer)
			|| c >= 0x1900 && c <= 0x1AAF // (Limbu, Tai Le, New Tai Lue, Khmer symbols, Buginese, Tai Tham)
			|| c >= 0x1B00 && c <= 0x1C4F // (Balinese, Sundanese, Batak, Lepcha)
			|| c >= 0xA800 && c <= 0xA82F || c >= 0xA840 && c <= 0xA8FF // (Syloti Nagri, Phags-pa, Saurashtra, Devanagari Extended)
			|| c >= 0xA900 && c <= 0xA9FF || c >= 0xAA00 && c <= 0xAA7F || c >= 0xAAE0 && c <= 0xAAFF || c >= 0xABC0 && c <= 0xABFF // (Kayah Li, Rejang, Javanese, Cham, Myanmar Extended, Meetei Mayek)
			|| c >= 0x11000 && c <= 0x11FFF; // (Brahmi, Kaithi, Chakma, Sharada, Grantha, Newa, Tirhuta...)

	// (joiners and the like inside a complex script's run: shaped with it)
	public static inline function joins(c:Int):Bool
		return c == 0x200C || c == 0x200D || c == 0x25CC;
}

// A platform's text stack behind helder.text's layout: fallback and
// discovery (a file and face), shaping (a face's glyphs for a run of text)
// and rasterising (a glyph's coverage).
interface TextBackend {
	// "HarfBuzz", "DirectWrite", "Core Text"
	function name():String;
	// text[start...end] in font, its direction rtl: its glyphs into out, in
	// visual order, in font units (offsets y up); false: not shaped
	function shape(font:FontFile, text:String, start:Int, end:Int, rtl:Bool, out:ShapedGlyphs):Bool;
	// a glyph's coverage at size pixels, its origin dx (0 to 1) pixels right
	// of a pixel's edge: into out; false: helder's rasterizer draws it
	function rasterize(font:FontFile, glyph:Int, size:Float, dx:Float, out:GlyphBitmap):Bool;
	// a file and face index with the character, as the system falls back
	// (lang: a BCP 47 tag, or null); null: none
	function fallback(cp:Int, ?lang:String):Null<{path:String, index:Int}>;
	// the system's face of a family closest to weight and italic; null: none
	function find(family:String, weight:Int, italic:Bool):Null<{path:String, index:Int}>;
	// how its rasters are blended where the system blends them otherwise
	// than as plain coverage (Windows' grayscale text: its contrast and
	// gamma, GlyphBlend); null: as they are
	function blend():Null<GlyphBlend>;
}

// Windows' grayscale text blend, as Direct2D draws DirectWrite's coverage
// (after Windows Terminal's AtlasEngine, MIT, which writes it out): the
// coverage's contrast enhanced, less for light text (grayscale enhanced
// contrast, the user's ClearType tuning), then corrected for the text
// colour's intensity by the gamma's ratios, so that light text on dark is
// not thinner than dark on light. The renderer's shader applies it to the
// glyphs the platform drew (AtlasGlyph.native).
class GlyphBlend {
	// the four ratios of the alpha correction, the grayscale enhanced contrast
	public final ratios:Array<Float>;
	public final contrast:Float;

	public function new(gamma:Float, contrast:Float) {
		this.contrast = contrast;
		ratios = GlyphBlend.ratiosOf(gamma);
	}

	// (Direct2D's table, a row each tenth of gamma 1.0 to 2.2, scaled as Windows Terminal scales it)
	static final TABLE = [
		[0.0000, 0.0000, 0.0000, 0.0000], [0.0166, -0.0807, 0.2227, -0.0751], [0.0350, -0.1760, 0.4325, -0.1370], [0.0543, -0.2821, 0.6302, -0.1876],
		[0.0739, -0.3963, 0.8167, -0.2287], [0.0933, -0.5161, 0.9926, -0.2616], [0.1121, -0.6395, 1.1588, -0.2877], [0.1300, -0.7649, 1.3159, -0.3080],
		[0.1469, -0.8911, 1.4644, -0.3234], [0.1627, -1.0170, 1.6051, -0.3347], [0.1773, -1.1420, 1.7385, -0.3426], [0.1908, -1.2652, 1.8650, -0.3476],
		[0.2031, -1.3864, 1.9851, -0.3501]
	];

	public static function ratiosOf(gamma:Float):Array<Float> {
		var g = gamma < 1 ? 1.0 : gamma > 2.2 ? 2.2 : gamma;
		var r = TABLE[Math.round((g - 1) / 0.1)];
		var n13 = 65536 / (255 * 255) * 4, n24 = 256 / 255 * 4;
		return [n13 * r[0] / 4, n24 * r[1] / 4, n13 * r[2] / 4, n24 * r[3] / 4];
	}

	// a coverage a in a colour r, g, b (0 to 1, straight): what is blended
	// (the shader's, UiShader, the same)
	public function apply(a:Float, r:Float, g:Float, b:Float):Float {
		var light = 3 - 4 * (0.30 * r + 0.59 * g + 0.11 * b);
		var k = contrast * (light < 0 ? 0 : light > 1 ? 1 : light);
		var f = 0.25 * r + 0.5 * g + 0.25 * b;
		a = a * (k + 1) / (a * k + 1);
		return a + a * (1 - a) * ((ratios[0] * f + ratios[1]) * a + (ratios[2] * f + ratios[3]));
	}
}

// A shaped run's glyphs (kept for the next run: its columns grow)
class ShapedGlyphs {
	public var count = 0;
	public var ids = new Vector<Int>(16);
	public var clusters = new Vector<Int>(16);
	public var advances = new Vector<Float>(16);
	public var dx = new Vector<Float>(16);
	public var dy = new Vector<Float>(16);

	public function new() {}

	public function reset(n:Int) {
		count = 0;
		if (ids.length >= n) return;
		ids = new Vector(n);
		clusters = new Vector(n);
		advances = new Vector(n);
		dx = new Vector(n);
		dy = new Vector(n);
	}

	public inline function push(id:Int, cluster:Int, advance:Float, x:Float, y:Float) {
		if (count == ids.length) {
			var n = count * 2;
			inline function ints(v:Vector<Int>) {
				var w = new Vector<Int>(n);
				Vector.blit(v, 0, w, 0, count);
				return w;
			}
			inline function floats(v:Vector<Float>) {
				var w = new Vector<Float>(n);
				Vector.blit(v, 0, w, 0, count);
				return w;
			}
			ids = ints(ids);
			clusters = ints(clusters);
			advances = floats(advances);
			dx = floats(dx);
			dy = floats(dy);
		}
		ids[count] = id;
		clusters[count] = cluster;
		advances[count] = advance;
		dx[count] = x;
		dy[count] = y;
		count++;
	}
}

// A glyph's coverage as a platform drew it: width x height bytes (0 to
// 255), its top left left and top pixels from the origin (y down)
class GlyphBitmap {
	public var width = 0;
	public var height = 0;
	public var left = 0;
	public var top = 0;
	public var pixels = Bytes.alloc(0);

	public function new() {}

	public function size(w:Int, h:Int) {
		width = w;
		height = h;
		if (pixels.length < w * h) pixels = Bytes.alloc(w * h * 2);
	}
}
