import haxe.io.Bytes;
import haxe.Json;
import helder.text.*;
import helder.text.GlyphPipeline;

using StringTools;

// helder.text's CoreGraphics glyph pipeline (GlyphPipeline) against
// CoreGraphics' own output, captured on macOS 15.3 (24D60) by Rune
// (github.com/anomalyco/rune, MIT; tests/text/coretext/README.md): the
// dilation radius against the native luminance sweep, dilated paths
// against CoreGraphics' (to 1e-11 px), its autohinter's transforms (to
// 1e-12), and Inter Regular's glyph masks with font smoothing on (dark and
// white ink) and off, at hinted and unhinted sizes and two phases, within 3
// levels of 255, as Rune's port lands. Run from TextTest (Eval) and on its own:
//
//   <tool> -cp src -cp tests/text --run CoreGraphicsTest
class CoreGraphicsTest {
	static var checks = 0;
	static var failed = 0;
	static final DIR = "tests/text/coretext";
	// corpus tiles: the pen at x 8, the baseline 24 px above the bottom
	static inline var TW = 96;
	static inline var TH = 112;

	static function main() {
		run();
		Sys.println('CoreGraphicsTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	public static function run():{checks:Int, failed:Int} {
		radii();
		dilation();
		hints();
		steps();
		masks();
		return {checks: checks, failed: failed};
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('CoreGraphicsTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function rgb(c:Array<Float>):Int
		return Math.round(c[0] * 255) << 16 | Math.round(c[1] * 255) << 8 | Math.round(c[2] * 255);

	// (the radius CoreGraphics dilates by, against its luminance sweep at 32 ppem: greys and colours)
	static function radii() {
		var sweep:Dynamic = Json.parse(sys.io.File.getContent('$DIR/sweep.json'));
		var steps:Int = sweep.steps, ppem:Float = sweep.ppem;
		var transitions:Array<Array<Float>> = sweep.transitions;
		var bad = 0;
		// (the sweep's greys are 1/4096 steps: the bucket of each 8-bit grey within it)
		for (v in 0...256) {
			var i = Math.round(v / 255 * steps), want = 0.0;
			for (t in transitions)
				if (t[0] <= i) want = t[1];
			// (an 8-bit grey between the sweep's steps: its own bucket's transition)
			var got = GlyphPipeline.radius(ppem, GlyphPipeline.bucket(v << 16 | v << 8 | v));
			if (Math.abs(got - want) > 1e-12 && !near(v, steps, transitions)) bad++;
		}
		check("radius: the luminance sweep's grey transitions", bad == 0, '$bad greys');
		var chroma:Array<Array<Dynamic>> = sweep.chromatic;
		for (c in chroma) {
			var col:Array<Float> = c[0];
			check('radius: ${col}', GlyphPipeline.radius(ppem, GlyphPipeline.bucket(rgb(col))) == (c[1] : Float));
		}
		// (#1d1e22 at 8, 32, 51, 52 and 200 ppem: the f32 cap)
		for (r in [[8.0, 0.0464], [32.0, 0.1856], [51.0, 0.29579999999999995], [52.0, 0.30000001192092896], [200.0, 0.30000001192092896]])
			check('radius: #1d1e22 at ${r[0]} ppem', Math.abs(GlyphPipeline.radius(r[0], GlyphPipeline.bucket(0x1d1e22)) - r[1]) < 1e-15,
				"" + GlyphPipeline.radius(r[0], GlyphPipeline.bucket(0x1d1e22)));
		check("bucket: #e6e6e6 3, #f1f1f1 4, #ff0000 1",
			GlyphPipeline.bucket(0xe6e6e6) == 3 && GlyphPipeline.bucket(0xf1f1f1) == 4 && GlyphPipeline.bucket(0xff0000) == 1);
	}

	// (a grey whose 1/4096 neighbourhood holds a transition: rounding to 8 bits can land either side)
	static function near(v:Int, steps:Int, transitions:Array<Array<Float>>):Bool {
		for (t in transitions)
			if (t[0] > 0 && Math.abs(v / 255 * steps - t[0]) < steps / 255) return true;
		return false;
	}

	static function path(rows:Array<Array<Float>>):GlyphPath {
		var p = new GlyphPath();
		for (r in rows)
			switch Std.int(r[0]) {
				case 0: p.move(r[1], r[2]);
				case 1: p.line(r[1], r[2]);
				case 2: p.quad(r[1], r[2], r[3], r[4]);
				case 3: p.cubic(r[1], r[2], r[3], r[4], r[5], r[6]);
				case _: p.close();
			}
		return p;
	}

	// (the largest coordinate difference; -1: the commands differ)
	static function pathError(a:GlyphPath, b:GlyphPath):Float {
		if (a.nc != b.nc || a.np != b.np) return -1;
		for (i in 0...a.nc)
			if (a.cmd[i] != b.cmd[i]) return -1;
		var worst = 0.0;
		for (i in 0...a.np)
			worst = Math.max(worst, Math.abs(a.pt[i] - b.pt[i]));
		return worst;
	}

	static function dilation() {
		var cases:Array<Dynamic> = Json.parse(sys.io.File.getContent('$DIR/dilation.json'));
		var g = new GlyphPipeline(), worst = 0.0, structure = 0;
		for (c in cases) {
			var d = GlyphPipeline.radius(c.ppem, GlyphPipeline.bucket(rgb(c.color)));
			var out = new GlyphPath();
			g.dilate(path(c.path), d, d, out);
			var e = pathError(out, path(c.oracle));
			if (e < 0) structure++ else worst = Math.max(worst, e);
		}
		check('dilation: ${cases.length} paths as CoreGraphics dilates them', structure == 0 && worst < 1e-11, '$structure differ in structure, max error $worst px');
	}

	static function hints() {
		var rows:Array<Dynamic> = [for (l in sys.io.File.getContent('$DIR/hints.jsonl').split("\n")) if (l.trim() != "") Json.parse(l)];
		var metrics = new Map<String, HintMetrics>();
		for (r in rows)
			if (r.valid == 1) metrics.set(r.font, new HintMetrics(r.upem, r.otop, r.Xtop, r.fonttop, r.stem));
		var count = 0, worst = 0.0, mismatches = 0;
		for (r in rows) {
			var t = GlyphPipeline.autohint(metrics.get(r.font), r.ppem, r.d);
			if ((t != null) != (r.valid == 1)) mismatches++;
			if (t != null) {
				count++;
				var want:Array<Float> = r.transform;
				for (i in 0...t.values.length)
					worst = Math.max(worst, Math.abs(t.values[i] - want[i]));
			}
		}
		check("autohint: CoreGraphics' 180 transforms", count == 180 && mismatches == 0 && worst < 1e-12, '$count transforms, $mismatches mismatches, max error $worst');
		var inter = FontFile.parse(sys.io.File.getBytes('$DIR/Inter-Regular.ttf'));
		var m = HintMetrics.of(inter);
		check("autohint: Inter's metrics as CoreGraphics reads them",
			m != null && m.upem == 2048 && m.xHeight == 1132 && m.capHeight == 1490 && m.maxY == 2269 && m.stemHeight == 0,
			m == null ? "none" : '${m.upem} ${m.xHeight} ${m.capHeight} ${m.maxY} ${m.stemHeight}');
	}

	// (CoreGraphics' subpixel quantisation: fifths to wholes by ppem; the pen floored)
	static function steps() {
		check("steps: fifths, quarters, thirds, halves, wholes",
			[for (p in [5.0, 8.3, 8.4, 11.1, 11.2, 16.6, 16.7, 33.3, 33.4, 80]) GlyphPipeline.steps(p)].join(",") == "5,5,4,4,3,3,2,2,1,1",
			[for (p in [5.0, 8.3, 8.4, 11.1, 11.2, 16.6, 16.7, 33.3, 33.4, 80]) GlyphPipeline.steps(p)].join(","));
		// (13 ppem: thirds; a pen at 10.32 floors to 10 + 0/3, 10.34 to 10 + 1/3 = 20/60; 10.99 to 10 + 2/3)
		check("pen: floored to thirds at 13 ppem",
			GlyphPipeline.penPixel(10.32, 13) == 10 && GlyphPipeline.penPhase(10.32, 13) == 0 && GlyphPipeline.penPhase(10.34, 13) == 20
			&& GlyphPipeline.penPhase(10.99, 13) == 40 && GlyphPipeline.penPixel(-0.1, 13) == -1 && GlyphPipeline.penPhase(-0.1, 13) == 40);
		// (a pen a hair (under 1/512) short of a step: on it)
		check("pen: noise under 1/512 px snapped", GlyphPipeline.penPixel(10.9999, 40) == 11 && GlyphPipeline.penPhase(10.9999, 40) == 0);
	}

	// Inter Regular's masks through each mode against CoreGraphics', smoothing on and off
	static function masks() {
		var index:Array<Dynamic> = Json.parse(sys.io.File.getContent('$DIR/masks.json'));
		var blob = sys.io.File.getBytes('$DIR/masks.bin');
		var inter = FontFile.parse(sys.io.File.getBytes('$DIR/Inter-Regular.ttf'));
		var g = new GlyphPipeline(), r = new Rasterizer(0, 0);
		for (on in [true, false]) {
			var s = new Stats();
			for (c in index) {
				var ppem:Float = c.ppem, phase:Array<Float> = c.phase;
				var d = on ? GlyphPipeline.radius(ppem, GlyphPipeline.bucket(rgb(c.color))) : 0.0;
				var ours = tile(g, r, inter, c.glyph, ppem, phase[0], phase[1], d);
				s.add(ours, reference(blob, on ? c.on : c.off));
			}
			var tag = on ? "on" : "off";
			Sys.println('CoreGraphicsTest: smoothing $tag against CoreGraphics: ${s.line()}');
			check('masks: smoothing $tag within 3 levels of CoreGraphics, mean under 0.2', s.max <= 3 && s.mae() < 0.2, s.line());
		}
	}

	static function tile(g:GlyphPipeline, r:Rasterizer, font:FontFile, glyph:Int, ppem:Float, px:Float, py:Float, d:Float):Bytes {
		var out = Bytes.alloc(TW * TH);
		out.fill(0, out.length, 0);
		if (!g.drawAt(font, glyph, ppem, px, py, d, 0, r)) return out;
		var m = Bytes.alloc(r.width * r.height);
		r.writeTo(m, 0, r.width);
		for (row in 0...r.height)
			for (col in 0...r.width) {
				var x = 8 + g.left + col, y = TH - 24 + g.top + row;
				if (x >= 0 && y >= 0 && x < TW && y < TH) out.set(y * TW + x, m.get(row * r.width + col));
			}
		return out;
	}

	static function reference(blob:Bytes, crop:Array<Int>):Bytes {
		var out = Bytes.alloc(TW * TH);
		out.fill(0, out.length, 0);
		var x0 = crop[0], y0 = crop[1], cw = crop[2], ch = crop[3], at = crop[4];
		for (y in 0...ch)
			out.blit((y0 + y) * TW + x0, blob, at + y * cw, cw);
		return out;
	}
}

// differences over the union of both masks' ink and a pixel around it, as Rune's
private class Stats {
	public var pixels = 0;
	public var sum = 0;
	public var max = 0;
	public var hist = [0, 0, 0, 0, 0];
	public var cases = 0;

	public function new() {}

	public function add(a:Bytes, b:Bytes) {
		var w = 96, h = 112, x0 = w, y0 = h, x1 = 0, y1 = 0;
		for (y in 0...h)
			for (x in 0...w)
				if (a.get(y * w + x) != 0 || b.get(y * w + x) != 0) {
					if (x < x0) x0 = x;
					if (y < y0) y0 = y;
					if (x + 1 > x1) x1 = x + 1;
					if (y + 1 > y1) y1 = y + 1;
				}
		cases++;
		for (y in (y0 > 0 ? y0 - 1 : 0)...(y1 + 1 < h ? y1 + 1 : h))
			for (x in (x0 > 0 ? x0 - 1 : 0)...(x1 + 1 < w ? x1 + 1 : w)) {
				var d = Std.int(Math.abs(a.get(y * w + x) - b.get(y * w + x)));
				pixels++;
				sum += d;
				if (d > max) max = d;
				hist[d > 4 ? 4 : d]++;
			}
	}

	public function mae():Float
		return sum / (pixels > 0 ? pixels : 1);

	public function line():String {
		inline function pct(n:Int)
			return Math.round(100000.0 * n / (pixels > 0 ? pixels : 1)) / 1000;
		return '$cases masks, $pixels pixels, mean ${Math.round(mae() * 100000) / 100000}, max $max | 0: ${pct(hist[0])}% 1: ${pct(hist[1])}% 2: ${pct(hist[2])}% 3: ${pct(hist[3])}% >3: ${pct(hist[4])}%';
	}
}
