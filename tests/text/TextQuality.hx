import haxe.io.Bytes;
import helder.image.PngDecoder;
import helder.image.PngEncoder;
import helder.text.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The text-quality lane: helder.text's own engine against macOS's CoreText.
// Sample strings (Inter Regular and Bold at seven sizes, DejaVu Sans at
// three, a paragraph of Inter 16/26) laid out by helder's engine, drawn in
// four inks on their pages (dark on light, light grey and near white on
// dark, a mid blue on light), at 1x and 2x, the way helder.ui's Renderer
// draws them (each glyph's coverage from the atlas, blended in sRGB-encoded
// space over the page) in each font smoothing mode, and compared with
// CoreText drawing the same glyphs at the same pens (CTFontDrawGlyphs
// through helder's Core Text back end, CoreText.sheet, on a Mac: font
// smoothing on, and off as `-webkit-font-smoothing: antialiased`). After
// Rune's comparison (github.com/anomalyco/rune, MIT: text/pixel_compare.rs
// and research/23-text-quality.md), its cases and its numbers: the green
// channel's differences (share differing, share off by more than 8, the
// largest, the mean), the ink's weight against CoreText's (the summed
// distance from the page) and structural similarity (Gaussian SSIM, sigma
// 1.5, on each row's ink). "before" is the rasterizer helder had before
// (font-rs coverage, its own flattening, pens to the nearest quarter, no
// hinting or smoothing), kept here to measure against.
//
//   TextQuality reference <dir>          (macOS) CoreText's sheets into dir, and layout.txt
//   TextQuality compare <refs> <out>     helder's sheets against refs: out/report.md, heatmaps
//   TextQuality layout                   the layout's digests (refs are stale when they differ)
//   TextQuality sheets <dir>             helder's own sheets, named as CoreText's are
class TextQuality {
	static final SAMPLE = "IHT—/AVSog@8 Hamburgefonstiv";
	static final ASCII_SAMPLE = "IHT/AVSog@8 Hamburgefonstiv";
	static final PARAGRAPH = "The quick brown fox jumps over the lazy dog. AV To Wa Ty Yo LT fi fl ffi office flour 0123456789 ($4.50, 87%) — \"quoted\" & semicolons; colons: question? Incomprehensibilities and HYPERVENTILATION.";
	static final SIZES = [9.0, 11, 13, 16, 20, 24, 32];
	static final WIDTH = 640.0;
	static final FONTS = {
		regular: "tests/text/coretext/Inter-Regular.ttf",
		bold: "tests/text/coretext/Inter-Bold-subset.ttf",
		dejavu: "tests/canvas/fonts/DejaVuSans-canvas.ttf"
	};
	// ink on page (sRGB): name, ink, page; whether CoreText's smoothing-off sheets have it
	static final PAIRS:Array<Pair> = [
		{name: "light", fg: 0x1d1e22, bg: 0xfcfcfb, flat: true},
		{name: "dark", fg: 0xe6e6e6, bg: 0x1d1e22, flat: true},
		{name: "white", fg: 0xfcfcfb, bg: 0x1d1e22, flat: false},
		{name: "blue", fg: 0x296d9a, bg: 0xfcfcfb, flat: false}
	];
	static final SCALES = [1.0, 2.0];

	static function main() {
		var args = Sys.args();
		// (helder's own shaping, whatever the lane's engine: the references draw its glyphs)
		Shaping.engine = Shaping.HELDER;
		switch args[0] {
			case "reference":
				reference(args[1]);
			case "compare":
				Sys.exit(compare(args[1], args[2]) ? 0 : 1);
			case "layout":
				Sys.print(layoutFile());
			case "sheets":
				sheets(args[1]);
			case _:
				Sys.println("TextQuality reference <dir> | compare <refs> <out> | layout");
				Sys.exit(1);
		}
	}

	// --- the cases

	static var faces:Null<{regular:FontFile, bold:FontFile, dejavu:FontFile}> = null;

	static function font(path:String):FontFile {
		var f = FontFile.parse(File.getBytes(path));
		f.path = FileSystem.fullPath(path);
		f.engine = Shaping.HELDER;
		return f;
	}

	static function cases():Array<Case> {
		if (faces == null) faces = {regular: font(FONTS.regular), bold: font(FONTS.bold), dejavu: font(FONTS.dejavu)};
		var out:Array<Case> = [], y = 4.0;
		function row(name:String, f:FontFile, path:String, size:Float, text:String) {
			var h = Math.ceil(size * 1.25) + 6;
			out.push({
				name: name,
				font: f,
				path: path,
				size: size,
				lineHeight: 1.25,
				wrap: 1e9,
				text: text,
				x: 16,
				y: y + 3,
				region: [0, y, WIDTH, h],
				whole: false
			});
			y += h;
		}
		for (s in SIZES)
			row('regular $s', faces.regular, FONTS.regular, s, SAMPLE);
		for (s in SIZES)
			row('bold $s', faces.bold, FONTS.bold, s, SAMPLE);
		for (s in [11.0, 13, 16])
			row('dejavu $s', faces.dejavu, FONTS.dejavu, s, ASCII_SAMPLE);
		var top = Math.fceil(y) + 4;
		out.push({
			name: "paragraph 16/26",
			font: faces.regular,
			path: FONTS.regular,
			size: 16,
			lineHeight: 26 / 16,
			wrap: 567,
			text: PARAGRAPH,
			x: 49,
			y: top + 40,
			region: [0, top + 30, WIDTH, 90],
			whole: true
		});
		return out;
	}

	static function sheetHeight(cs:Array<Case>):Float {
		var last = cs[cs.length - 1];
		return last.region[1] - 30 + 130;
	}

	// each case's glyphs at scale: id, the pen x (device pixels, not quantised) and the whole-pixel baseline, as Renderer.glyphs places them
	static function glyphs(c:Case, scale:Float):Array<{id:Int, x:Float, y:Int}> {
		var set = new FontSet(c.font, [], c.size);
		var t = new TextLayout(c.text, set, c.lineHeight, c.wrap);
		var out:Array<{id:Int, x:Float, y:Int}> = [];
		for (l in t.lines) {
			var by = Math.round((c.y + l.top + l.baseline) * scale);
			var lineX = Math.fround(c.x * scale);
			for (i in l.glyphStart...l.glyphEnd) {
				var ch = t.glyphChar(i);
				if (ch == 32 || ch == 10 || ch == 9 || t.glyphHidden(i)) continue;
				out.push({id: t.glyphId(i), x: lineX + (t.glyphX(i) + t.glyphOffsetX(i)) * scale, y: by + Math.round(t.glyphOffsetY(i) * scale)});
			}
		}
		return out;
	}

	static function digest(scale:Float):String {
		var b = new StringBuf();
		for (c in cases())
			for (g in glyphs(c, scale))
				b.add('${g.id} ${g.x} ${g.y}\n');
		return haxe.crypto.Sha1.encode(b.toString()).substr(0, 16);
	}

	static function layoutFile():String
		return [for (s in SCALES) '${Std.int(s)}x ${digest(s)}\n'].join("");

	// --- CoreText's sheets (macOS)

	static function reference(dir:String) {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (hxmc.unsafe.Mem.os() != 1) throw "TextQuality reference: Core Text is macOS's";
		FileSystem.createDirectory(dir);
		var cs = cases();
		for (scale in SCALES) {
			var w = Std.int(WIDTH * scale), h = Std.int(sheetHeight(cs) * scale);
			var runs:Array<helder.text.mac.CoreText.SheetRun> = [];
			for (c in cs) {
				var gs = glyphs(c, scale);
				runs.push({path: c.font.path, face: 0, size: c.size, ids: [for (g in gs) g.id], xs: [for (g in gs) g.x], ys: [for (g in gs) (g.y : Float)]});
			}
			for (smooth in [true, false])
				for (p in PAIRS) {
					if (!smooth && !p.flat) continue;
					var green = helder.text.mac.CoreText.sheet(w, h, scale, p.bg, p.fg, smooth, runs);
					var name = '$dir/${smooth ? "" : "flat-"}${p.name}-${Std.int(scale)}x.png';
					File.saveBytes(name, grey(green, w, h));
					Sys.println('TextQuality: $name');
				}
		}
		File.saveContent('$dir/layout.txt', layoutFile());
		#else
		throw "TextQuality reference: Core Text is macOS's";
		#end
	}

	static function sheets(dir:String) {
		FileSystem.createDirectory(dir);
		var cs = cases();
		for (scale in SCALES)
			for (smooth in [true, false])
				for (p in PAIRS) {
					if (!smooth && !p.flat) continue;
					var w = Std.int(WIDTH * scale), h = Std.int(sheetHeight(cs) * scale);
					File.saveBytes('$dir/${smooth ? "" : "flat-"}${p.name}-${Std.int(scale)}x.png', grey(draw(smooth ? "on" : "off", p, scale, cs), w, h));
				}
		File.saveContent('$dir/layout.txt', layoutFile());
	}

	static function grey(green:Bytes, w:Int, h:Int):Bytes {
		var rgba = Bytes.alloc(w * h * 4);
		for (i in 0...w * h) {
			var v = green.get(i);
			rgba.set(4 * i, v);
			rgba.set(4 * i + 1, v);
			rgba.set(4 * i + 2, v);
			rgba.set(4 * i + 3, 255);
		}
		return PngEncoder.encode(rgba, w, h, true);
	}

	static function readGreen(path:String):{w:Int, h:Int, g:Bytes} {
		var d = PngDecoder.decode(File.getBytes(path));
		var g = Bytes.alloc(d.width * d.height);
		for (i in 0...d.width * d.height)
			g.set(i, d.rgba.get(4 * i + 1));
		return {w: d.width, h: d.height, g: g};
	}

	// --- helder's sheets

	// a sheet in a mode: "before" (the rasterizer helder had), "off", "on"; green channel
	static function draw(mode:String, p:Pair, scale:Float, cs:Array<Case>):Bytes {
		var w = Std.int(WIDTH * scale), h = Std.int(sheetHeight(cs) * scale);
		var g = Bytes.alloc(w * h), page = (p.bg >> 8) & 255, ink = (p.fg >> 8) & 255;
		g.fill(0, g.length, page);
		var atlas = new GlyphAtlas(2048, 2048);
		atlas.smoothing = mode == "off" ? FontSmoothing.Off : FontSmoothing.On;
		var legacy = new Legacy();
		for (c in cs) {
			var size = c.size * scale;
			for (gl in glyphs(c, scale)) {
				var cov:Bytes, cw:Int, ox:Int, oy:Int, bx:Int, by:Int, bw:Int, bh:Int;
				if (mode == "before") {
					if (!legacy.draw(c.font, gl.id, size, gl.x)) continue;
					cov = legacy.pixels;
					cw = legacy.w;
					ox = 0;
					oy = 0;
					bw = legacy.w;
					bh = legacy.h;
					bx = legacy.left;
					by = gl.y + legacy.top;
				} else {
					var a = atlas.get(c.font, gl.id, size, GlyphAtlas.phase(gl.x, size), false, 0, p.fg);
					if (a.w == 0) continue;
					cov = atlas.pixels;
					cw = atlas.width;
					ox = a.x;
					oy = a.y;
					bw = a.w;
					bh = a.h;
					bx = GlyphAtlas.pixel(gl.x, size) + a.left;
					by = gl.y + a.top;
				}
				// (source over in sRGB-encoded space, as the Renderer's premultiplied blend into a non-sRGB target; each glyph written as a byte)
				for (yy in 0...bh)
					for (xx in 0...bw) {
						var X = bx + xx, Y = by + yy;
						if (X < 0 || Y < 0 || X >= w || Y >= h) continue;
						var k = cov.get((oy + yy) * cw + ox + xx) / 255;
						if (k == 0) continue;
						var o = Y * w + X;
						g.set(o, Std.int(Math.min(255, Math.max(0, Math.fround(ink * k + g.get(o) * (1 - k))))));
					}
			}
		}
		return g;
	}

	// --- comparing

	static function compare(refs:String, out:String):Bool {
		if (!FileSystem.exists('$refs/layout.txt')) {
			Sys.println('TextQuality: no references in $refs (they are drawn on a Mac: the system-text lane, `TextQuality reference`)');
			return false;
		}
		var want = layoutFile(), have = File.getContent('$refs/layout.txt');
		if (want != have) {
			Sys.println('TextQuality: the references in $refs are stale: drawn from layout $have, now $want (draw them again on a Mac: the system-text lane writes bin/text/coretext)');
			return false;
		}
		FileSystem.createDirectory(out);
		var cs = cases();
		var rows:Array<Row> = [];
		for (scale in SCALES)
			for (smooth in [true, false])
				for (p in PAIRS) {
					if (!smooth && !p.flat) continue;
					var file = '${smooth ? "" : "flat-"}${p.name}-${Std.int(scale)}x.png';
					var ref = readGreen('$refs/$file');
					for (mode in (smooth ? ["before", "on"] : ["before", "off"])) {
						var ours = draw(mode, p, scale, cs);
						if (ref.w * ref.h != ours.length) throw '$file: ${ref.w}x${ref.h}, ours ${ours.length} pixels';
						File.saveBytes('$out/$mode-$file', grey(ours, ref.w, ref.h));
						File.saveBytes('$out/heat-$mode-$file', heatmap(ours, ref.g, ref.w, ref.h));
						for (c in cs)
							rows.push({
								reference: smooth ? "smoothing on" : "smoothing off",
								pair: p,
								scale: scale,
								mode: mode,
								c: c,
								s: Stats.of(ours, ref.g, ref.w, ref.h, c, scale)
							});
					}
				}
		var md = report(rows);
		File.saveContent('$out/report.md', md);
		Sys.println(md);
		// (held to what the port reaches: each mode closer than before, and within 4 levels of CoreText, on every pair and scale)
		var ok = true;
		for (scale in SCALES)
			for (p in PAIRS)
				for (ref in ["smoothing on", "smoothing off"]) {
					var before = pooled(rows, ref, p.name, scale, "before", false), after = pooled(rows, ref, p.name, scale, ref == "smoothing on" ? "on" : "off", false);
					if (before.pixels == 0) continue;
					if (after.meanabs() > before.meanabs() || after.ssim() < before.ssim()) {
						Sys.println('TextQuality: FAIL: ${p.name} ${scale}x against CoreText with $ref: further than before');
						ok = false;
					}
					// (CoreText's within a few levels: 3 on CI's sheets; a glyph placed or hinted otherwise is tens)
					for (whole in [false, true]) {
						var s = pooled(rows, ref, p.name, scale, ref == "smoothing on" ? "on" : "off", whole);
						if (s.max > 4 || s.ssim() < 0.999) {
							Sys.println('TextQuality: FAIL: ${p.name} ${scale}x against CoreText with $ref: ${s.max} levels off at most, SSIM ${s.ssim()}');
							ok = false;
						}
					}
				}
		return ok;
	}

	static function pooled(rows:Array<Row>, ref:String, pair:String, scale:Float, mode:String, whole:Bool):Stats {
		var s = new Stats();
		for (r in rows)
			if (r.reference == ref && r.pair.name == pair && r.scale == scale && r.mode == mode && r.c.whole == whole) s.add(r.s);
		return s;
	}

	static function report(rows:Array<Row>):String {
		var b = new StringBuf();
		b.add("# helder.text's engine against CoreText\n\n");
		b.add("Sample rows (Inter Regular and Bold 9 to 32, DejaVu Sans 11 to 16) pooled by pixel, and the Inter 16/26 paragraph; ");
		b.add("green channel, 0 to 255. weight: helder's ink over CoreText's (1 is the same); SSIM: mean of the rows' structural similarity; ");
		b.add("|d|: the share of pixels off by 0, 1 to 2, 3 to 8, 9 to 32 and more.\n\n");
		for (ref in ["smoothing on", "smoothing off"]) {
			b.add('## Against CoreText with $ref\n\n');
			b.add("| ink on page | scale | engine | SSIM | weight | mean abs | differ | >8 | max | |d| 0 / 1-2 / 3-8 / 9-32 / >32 |\n");
			b.add("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n");
			for (scale in SCALES)
				for (p in PAIRS)
					for (whole in [false, true])
						for (mode in ["before", ref == "smoothing on" ? "on" : "off"]) {
							var s = pooled(rows, ref, p.name, scale, mode, whole);
							if (s.pixels == 0) continue;
							b.add('| ${p.name}${whole ? " paragraph" : ""} | ${Std.int(scale)}x | ${mode == "before" ? "before" : "smoothing " + mode} | ${f(s.ssim(), 4)} | ${f(s.weight(), 3)} | ${f(s.meanabs(), 3)} | ${f(100 * s.differ / s.pixels, 1)}% | ${f(100 * s.over8 / s.pixels, 2)}% | ${s.max} | ${[for (k in 0...5) f(100 * s.hist[k] / s.pixels, 1)].join(" / ")} |\n');
						}
			b.add("\n");
		}
		b.add("## Each row (light, against the mode's own reference)\n\n| case | scale | engine | SSIM | weight | mean abs | >8 | max |\n| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |\n");
		for (r in rows)
			if (r.pair.name == "light")
				b.add('| ${r.c.name} | ${Std.int(r.scale)}x | ${r.mode} vs ${r.reference} | ${f(r.s.ssim(), 4)} | ${f(r.s.weight(), 3)} | ${f(r.s.meanabs(), 3)} | ${f(100 * r.s.over8 / r.s.pixels, 2)}% | ${r.s.max} |\n');
		return b.toString();
	}

	static function f(v:Float, digits:Int):String {
		var k = Math.pow(10, digits), s = Std.string(Math.round(v * k) / k);
		var dot = s.indexOf(".");
		if (dot < 0) s += ".";
		while (s.length - s.indexOf(".") - 1 < digits)
			s += "0";
		return s;
	}

	// (grey where the same, red where helder has less ink than CoreText, blue where more; differences four times)
	static function heatmap(ours:Bytes, ref:Bytes, w:Int, h:Int):Bytes {
		var pa = ours.get(0), pb = ref.get(0), rgba = Bytes.alloc(w * h * 4);
		for (i in 0...w * h) {
			var a = ours.get(i), r = ref.get(i), ia = Std.int(Math.abs(a - pa)), ib = Std.int(Math.abs(r - pb));
			var k = Std.int(Math.min(255, Math.abs(ib - ia) * 4));
			var c = a == r ? [252 - (ia >> 2), 252 - (ia >> 2), 252 - (ia >> 2)] : ib > ia ? [255, 255 - k, 255 - k] : [255 - k, 255 - k, 255];
			rgba.set(4 * i, c[0]);
			rgba.set(4 * i + 1, c[1]);
			rgba.set(4 * i + 2, c[2]);
			rgba.set(4 * i + 3, 255);
		}
		return PngEncoder.encode(rgba, w, h, true);
	}
}

typedef Pair = {name:String, fg:Int, bg:Int, flat:Bool};

typedef Case = {
	name:String,
	font:FontFile,
	path:String,
	size:Float,
	lineHeight:Float,
	wrap:Float,
	text:String,
	x:Float,
	y:Float,
	region:Array<Float>,
	whole:Bool
};

typedef Row = {reference:String, pair:Pair, scale:Float, mode:String, c:Case, s:Stats};

// the differences over a case's region (its ink and a pixel around it; the paragraph: all of it)
class Stats {
	public var pixels = 0;
	public var differ = 0;
	public var over8 = 0;
	public var max = 0;
	public var abs = 0.0;
	public var inkOurs = 0.0;
	public var inkRef = 0.0;
	// |d| 0, 1-2, 3-8, 9-32, more
	public var hist = [0, 0, 0, 0, 0];
	// (SSIM: summed over the rows, and how many)
	public var ssimSum = 0.0;
	public var ssimRows = 0;

	public function new() {}

	public function add(o:Stats) {
		pixels += o.pixels;
		differ += o.differ;
		over8 += o.over8;
		if (o.max > max) max = o.max;
		abs += o.abs;
		inkOurs += o.inkOurs;
		inkRef += o.inkRef;
		for (k in 0...5)
			hist[k] += o.hist[k];
		ssimSum += o.ssimSum;
		ssimRows += o.ssimRows;
	}

	public function meanabs():Float
		return abs / (pixels > 0 ? pixels : 1);

	public function weight():Float
		return inkOurs / (inkRef > 1 ? inkRef : 1);

	public function ssim():Float
		return ssimRows > 0 ? ssimSum / ssimRows : 1;

	public static function of(a:Bytes, b:Bytes, w:Int, h:Int, c:Case, scale:Float):Stats {
		var rx = Math.round(c.region[0] * scale), ry = Math.round(c.region[1] * scale);
		var rx1 = Std.int(Math.min(w, rx + Math.round(c.region[2] * scale))), ry1 = Std.int(Math.min(h, ry + Math.round(c.region[3] * scale)));
		var pa = a.get(0), pb = b.get(0);
		var x0 = rx, y0 = ry, x1 = rx1, y1 = ry1;
		if (!c.whole) {
			x0 = w;
			y0 = h;
			x1 = 0;
			y1 = 0;
			for (y in ry...ry1)
				for (x in rx...rx1)
					if (a.get(y * w + x) != pa || b.get(y * w + x) != pb) {
						if (x < x0) x0 = x;
						if (y < y0) y0 = y;
						if (x + 1 > x1) x1 = x + 1;
						if (y + 1 > y1) y1 = y + 1;
					}
			if (x1 <= x0) return new Stats();
			x0 = Std.int(Math.max(rx, x0 - 1));
			y0 = Std.int(Math.max(ry, y0 - 1));
			x1 = Std.int(Math.min(rx1, x1 + 1));
			y1 = Std.int(Math.min(ry1, y1 + 1));
		}
		var s = new Stats();
		for (y in y0...y1)
			for (x in x0...x1) {
				var va = a.get(y * w + x), vb = b.get(y * w + x), d = Std.int(Math.abs(va - vb));
				s.pixels++;
				if (d > 0) s.differ++;
				if (d > 8) s.over8++;
				if (d > s.max) s.max = d;
				s.abs += d;
				s.inkOurs += Math.abs(va - pa);
				s.inkRef += Math.abs(vb - pb);
				s.hist[d == 0 ? 0 : d <= 2 ? 1 : d <= 8 ? 2 : d <= 32 ? 3 : 4]++;
			}
		s.ssimSum = ssimOf(a, b, w, x0, y0, x1 - x0, y1 - y0);
		s.ssimRows = 1;
		return s;
	}

	// Gaussian SSIM (sigma 1.5, 11 taps, population covariance, data range 1),
	// its mean over the crop less the window's half at its edges, as
	// scikit-image's structural_similarity(gaussian_weights=True) gives it
	static function ssimOf(a:Bytes, b:Bytes, stride:Int, x0:Int, y0:Int, w:Int, h:Int):Float {
		var r = 5, taps = [for (i in -r...r + 1) Math.exp(-i * i / (2 * 1.5 * 1.5))], sum = 0.0;
		for (t in taps)
			sum += t;
		taps = [for (t in taps) t / sum];
		var n = w * h;
		var A = [for (i in 0...n) a.get((y0 + Std.int(i / w)) * stride + x0 + i % w) / 255];
		var B = [for (i in 0...n) b.get((y0 + Std.int(i / w)) * stride + x0 + i % w) / 255];
		inline function reflect(i:Int, m:Int):Int {
			// (scipy's "reflect": d c b a | a b c d | d c b a)
			while (i < 0 || i >= m)
				i = i < 0 ? -i - 1 : 2 * m - i - 1;
			return i;
		}
		function blur(v:Array<Float>):Array<Float> {
			var t = [for (i in 0...n) 0.0], o = [for (i in 0...n) 0.0];
			for (y in 0...h)
				for (x in 0...w) {
					var s = 0.0;
					for (k in 0...taps.length)
						s += taps[k] * v[y * w + reflect(x + k - r, w)];
					t[y * w + x] = s;
				}
			for (y in 0...h)
				for (x in 0...w) {
					var s = 0.0;
					for (k in 0...taps.length)
						s += taps[k] * t[reflect(y + k - r, h) * w + x];
					o[y * w + x] = s;
				}
			return o;
		}
		var ma = blur(A), mb = blur(B);
		var aa = blur([for (i in 0...n) A[i] * A[i]]), bb = blur([for (i in 0...n) B[i] * B[i]]), ab = blur([for (i in 0...n) A[i] * B[i]]);
		var c1 = 0.01 * 0.01, c2 = 0.03 * 0.03, total = 0.0, count = 0;
		var px0 = w > 2 * r ? r : 0, py0 = h > 2 * r ? r : 0;
		for (y in py0...h - py0)
			for (x in px0...w - px0) {
				var i = y * w + x;
				var va = aa[i] - ma[i] * ma[i], vb = bb[i] - mb[i] * mb[i], cov = ab[i] - ma[i] * mb[i];
				total += ((2 * ma[i] * mb[i] + c1) * (2 * cov + c2)) / ((ma[i] * ma[i] + mb[i] * mb[i] + c1) * (va + vb + c2));
				count++;
			}
		return count > 0 ? total / count : 1;
	}
}

// helder's rasterizer as it was before CoreGraphics' pipeline (GlyphAtlas
// until this lane): the outline straight into the Rasterizer (its own
// flattening), a pixel wider than its box, the pen to the nearest quarter
class Legacy {
	public var pixels = Bytes.alloc(0);
	public var w = 0;
	public var h = 0;
	public var left = 0;
	public var top = 0;

	final r = new Rasterizer(0, 0);

	public function new() {}

	public function draw(font:FontFile, glyph:Int, size:Float, x:Float):Bool {
		var px = x + 0.5 / 4, ix = Math.floor(px), sub = Std.int((px - ix) * 4), dx = sub / 4;
		var b = font.bounds(glyph);
		if (!(b[2] > b[0] && b[3] > b[1])) return false;
		var scale = size / font.unitsPerEm;
		var x0 = Math.floor(b[0] * scale + dx), x1 = Math.ceil(b[2] * scale + dx);
		var y0 = Math.floor(-b[3] * scale), y1 = Math.ceil(-b[1] * scale);
		w = x1 - x0 + 1;
		h = y1 - y0 + 1;
		r.reset(w, h);
		r.scaleX = scale;
		r.scaleY = -scale;
		r.offsetX = dx - x0;
		r.offsetY = -y0;
		r.skew = 0;
		font.outline(glyph, r);
		if (pixels.length < w * h) pixels = Bytes.alloc(w * h * 2);
		r.writeTo(pixels, 0, w);
		left = ix + x0;
		top = y0;
		return true;
	}
}
