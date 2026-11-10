import Model;
import haxe.ds.Vector;
import helder.canvas.Canvas;
import helder.canvas.Paint;
import helder.canvas.Path;
import helder.text.FontFile;
import helder.text.Outline;

// A face traced from a font's outlines, so that a font made of outlines
// (Inter, a font of the user's) can be started from in Foundry's pen
// lines: each glyph drawn on the CPU, thinned to its skeleton (Zhang and
// Suen's, then the steps of a staircase taken out), the skeleton read as a
// graph (its ends and junctions, the chains between them, its loops), the
// spurs thinning leaves at corners pruned, each chain made into knots
// (Freehand's), the pen as wide as the strokes are (twice their distance
// from the edge along the skeleton, the median of the small letters'),
// the metrics and each glyph's spacing the font's. A pen's round ends
// give the length thinning takes off a stroke's end back. What comes out
// is the font drawn with one pen: a monoline's close, a high-contrast
// one's its skeleton.
class Trace {
	// pixels per unit (of 1000 to the em) the glyphs are thinned at
	public static inline var K = 0.3;
	public static inline var PAD = 4;
	static inline var TOLERANCE = 9.0;

	public static function face(font:FontFile, name:String):Face {
		var fs = Model.EM / font.unitsPerEm;
		function edge(cp:Int, top:Bool, fallback:Float):Float {
			var g = font.glyph(cp);
			if (g == 0) return fallback;
			var b = font.bounds(g);
			return b[0] == b[2] ? fallback : (top ? b[3] : b[1]) * fs;
		}
		var metrics:Metrics = {
			xHeight: Math.round(edge("x".code, true, 500)),
			capHeight: Math.round(edge("H".code, true, 700)),
			ascender: Math.round(Math.max(edge("d".code, true, 740), edge("l".code, true, 740))),
			descender: Math.round(edge("p".code, false, -230)),
			spacing: 0
		};
		var traced = new Map<String, Traced>(), widths = [], sides = [];
		for (group in Charset.groups) {
			if (group.name == "Accented") continue;
			for (char in group.chars) {
				var t = glyph(font, char, fs);
				if (t == null) continue;
				traced.set(char, t);
				if (group.name == "Lowercase") {
					for (w in t.widths)
						widths.push(w);
					sides.push(t.left);
					sides.push(t.right);
				}
			}
		}
		var width = widths.length == 0 ? Model.PEN.width : median(widths);
		var spacing = sides.length == 0 ? Model.METRICS.spacing : Math.max(0, Math.round(median(sides)));
		var face:Face = {
			name: name,
			pen: {width: Math.round(width), contrast: 0, angle: Model.PEN.angle, cap: Round},
			metrics: {xHeight: metrics.xHeight, capHeight: metrics.capHeight, ascender: metrics.ascender, descender: metrics.descender, spacing: spacing},
			glyphs: {}
		};
		// (each glyph's ink where the font's coordinates put it, its advance the font's:
		// the pen's ink is not the outline's, its spacing measured from the ink)
		for (char => t in traced) {
			var x0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY;
			for (c in Ink.contours(t.lines, face.pen))
				for (p in c) {
					if (p.x < x0) x0 = p.x;
					if (p.x > x1) x1 = p.x;
				}
			if (x0 > x1) continue;
			// (onto the guides, as a hand's line: a terminal cut across ends past them)
			var lines = [for (l in t.lines) Freehand.snap(l, face, [])];
			face = Model.with(face, char, {lines: lines, parts: [], left: Math.round(x0 - spacing), right: Math.round(t.advance - x1 - spacing)});
		}
		return face;
	}

	// one glyph's pen lines, in font units of 1000 to the em; null: none or empty
	static function glyph(font:FontFile, char:String, fs:Float):Null<Traced> {
		var g = font.glyph(Charset.code(char));
		if (g == 0) return null;
		var b = font.bounds(g);
		if (b[0] == b[2] || b[1] == b[3]) return null;
		var x0 = b[0] * fs, y1 = b[3] * fs;
		var w = Math.ceil((b[2] - b[0]) * fs * K) + PAD * 2, h = Math.ceil((b[3] - b[1]) * fs * K) + PAD * 2;
		var path = new Path();
		font.outline(g, new Collect(path, x -> (x * fs - x0) * K + PAD, y -> (y1 - y * fs) * K + PAD));
		var canvas = new Canvas(w, h);
		canvas.fill(path, Paint.solid(0xFF000000));
		var px = haxe.io.Bytes.alloc(w * h * 4);
		canvas.readPixels(px, 0, 0, w, h);
		var on = new Vector<Bool>(w * h);
		for (i in 0...w * h)
			on[i] = px.get(i * 4 + 3) >= 128;
		var unit = (x:Float, y:Float) -> {x: (x + 0.5 - PAD) / K + x0, y: y1 - (y + 0.5 - PAD) / K};
		var sk = skeleton(on, w, h, unit), lines = sk.lines, widths = sk.widths;
		if (lines.length == 0) return null;
		return {lines: lines, widths: widths, left: x0, right: font.advance(g) * fs - b[2] * fs, advance: font.advance(g) * fs};
	}

	// a shape's pen lines (thinned in place): unit, a pixel's place in font
	// units; widths, the strokes' along them (font units)
	public static function skeleton(on:Vector<Bool>, w:Int, h:Int, unit:(Float, Float) -> {x:Float, y:Float}):{lines:Array<Line>, widths:Array<Float>} {
		var dt = distances(on, w, h);
		thin(on, w, h);
		var lines:Array<Line> = [], widths = [];
		for (chain in chains(on, w, h, dt)) {
			var pts = [for (i in chain.pixels) unit(i % w, Std.int(i / w))];
			if (chain.start != null) pts.unshift(unit(chain.start.x, chain.start.y));
			if (chain.end != null) pts.push(unit(chain.end.x, chain.end.y));
			for (i in chain.pixels)
				widths.push((dt[i] / 3 * 2 + 0.5) / K);
			if (pts.length == 1 || chain.dot) {
				var c = pts[Std.int(pts.length / 2)];
				lines.push({knots: [{x: Math.round(c.x), y: Math.round(c.y)}]});
				continue;
			}
			for (_ in 0...2)
				pts = [for (i in 0...pts.length) chain.closed || i > 0 && i < pts.length - 1 ? {
					x: (pts[(i - 1 + pts.length) % pts.length].x + 2 * pts[i].x + pts[(i + 1) % pts.length].x) / 4,
					y: (pts[(i - 1 + pts.length) % pts.length].y + 2 * pts[i].y + pts[(i + 1) % pts.length].y) / 4
				} : pts[i]];
			if (chain.closed) pts.push(pts[0]);
			lines.push({knots: Freehand.knots(pts, chain.closed, TOLERANCE), closed: chain.closed});
		}
		return {lines: lines, widths: widths};
	}

	// each pixel's distance from the background, chamfered (3 a side, 4 a corner)
	public static function distances(on:Vector<Bool>, w:Int, h:Int):Vector<Int> {
		var d = new Vector<Int>(w * h);
		for (i in 0...w * h)
			d[i] = on[i] ? 1 << 20 : 0;
		for (y in 1...h - 1)
			for (x in 1...w - 1) {
				var i = y * w + x;
				if (d[i] == 0) continue;
				d[i] = min(d[i], min(d[i - 1] + 3, min(d[i - w] + 3, min(d[i - w - 1] + 4, d[i - w + 1] + 4))));
			}
		var y = h - 2;
		while (y > 0) {
			var x = w - 2;
			while (x > 0) {
				var i = y * w + x;
				if (d[i] != 0) d[i] = min(d[i], min(d[i + 1] + 3, min(d[i + w] + 3, min(d[i + w + 1] + 4, d[i + w - 1] + 4))));
				x--;
			}
			y--;
		}
		return d;
	}

	// the neighbours' offsets, clockwise from north (Zhang and Suen's P2 to P9)
	static final DX = [0, 1, 1, 1, 0, -1, -1, -1];
	static final DY = [-1, -1, 0, 1, 1, 1, 0, -1];

	// thinned to one pixel wide, in place: Zhang and Suen's two sub-passes
	// until nothing changes, then a pixel whose neighbours touch each other
	// without it (a staircase's step) taken out
	static function thin(on:Vector<Bool>, w:Int, h:Int) {
		var n = [for (_ in 0...8) false];
		var changed = true;
		while (changed) {
			changed = false;
			for (pass in 0...2) {
				var gone = [];
				for (y in 1...h - 1)
					for (x in 1...w - 1) {
						var i = y * w + x;
						if (!on[i]) continue;
						var count = 0, runs = 0;
						for (k in 0...8)
							if (n[k] = on[i + DY[k] * w + DX[k]]) count++;
						for (k in 0...8)
							if (!n[k] && n[(k + 1) % 8]) runs++;
						if (count < 2 || count > 6 || runs != 1) continue;
						if (pass == 0 && (n[0] && n[2] && n[4] || n[2] && n[4] && n[6])) continue;
						if (pass == 1 && (n[0] && n[2] && n[6] || n[0] && n[4] && n[6])) continue;
						gone.push(i);
					}
				for (i in gone)
					on[i] = false;
				if (gone.length > 0) changed = true;
			}
		}
		for (y in 1...h - 1)
			for (x in 1...w - 1) {
				var i = y * w + x;
				if (!on[i]) continue;
				var count = 0;
				for (k in 0...8)
					if (n[k] = on[i + DY[k] * w + DX[k]]) count++;
				if (count >= 2 && components(n) == 1 && !(count == 2 && opposite(n))) on[i] = false;
			}
	}

	// how many groups the set neighbours make, touching each other (corners too)
	static function components(n:Array<Bool>):Int {
		var group = [for (k in 0...8) n[k] ? k : -1];
		var merged = true;
		while (merged) {
			merged = false;
			for (a in 0...8)
				for (b in 0...8)
					if (group[a] >= 0 && group[b] >= 0 && group[a] != group[b] && Math.max(Math.abs(DX[a] - DX[b]), Math.abs(DY[a] - DY[b])) == 1) {
						var to = group[a] < group[b] ? group[a] : group[b], from = group[a] < group[b] ? group[b] : group[a];
						for (k in 0...8)
							if (group[k] == from) group[k] = to;
						merged = true;
					}
		}
		var seen = [];
		for (g in group)
			if (g >= 0 && seen.indexOf(g) < 0) seen.push(g);
		return seen.length;
	}

	// (two neighbours across from each other: the middle of a line)
	static inline function opposite(n:Array<Bool>):Bool
		return n[0] && n[4] || n[2] && n[6] || n[1] && n[5] || n[3] && n[7];

	// the skeleton's chains: between its ends and junctions, its loops, its
	// dots; the spurs (an end's short chain into a junction) left out
	static function chains(on:Vector<Bool>, w:Int, h:Int, dt:Vector<Int>):Array<Chain> {
		var degree = new Vector<Int>(w * h);
		for (y in 1...h - 1)
			for (x in 1...w - 1) {
				var i = y * w + x, c = 0;
				if (!on[i]) continue;
				for (k in 0...8)
					if (on[i + DY[k] * w + DX[k]]) c++;
				degree[i] = c;
			}
		inline function node(i:Int):Bool
			return on[i] && degree[i] != 2;
		var visited = new Vector<Bool>(w * h), out:Array<Chain> = [];
		function walk(from:Int, first:Int):Array<Int> {
			var chain = [from, first], prev = from, cur = first;
			while (!node(cur)) {
				visited[cur] = true;
				var next = -1;
				for (k in 0...8) {
					var j = cur + DY[k] * w + DX[k];
					if (j == prev || !on[j] || j == from && chain.length < 3) continue;
					if (node(j) || !visited[j]) {
						next = j;
						break;
					}
				}
				if (next < 0) break;
				chain.push(next);
				prev = cur;
				cur = next;
			}
			return chain;
		}
		var edges:Array<Array<Int>> = [];
		for (i in 0...w * h) {
			if (!node(i)) continue;
			if (degree[i] == 0) {
				out.push({pixels: [i], closed: false, dot: true});
				continue;
			}
			for (k in 0...8) {
				var j = i + DY[k] * w + DX[k];
				if (!on[j]) continue;
				if (node(j)) {
					if (i < j) edges.push([i, j]);
				} else if (!visited[j]) edges.push(walk(i, j));
			}
		}
		// loops: what is left, every pixel of it with two neighbours
		for (i in 0...w * h)
			if (on[i] && degree[i] == 2 && !visited[i]) {
				visited[i] = true;
				var next = -1;
				for (k in 0...8) {
					var j = i + DY[k] * w + DX[k];
					if (on[j]) {
						next = j;
						break;
					}
				}
				var chain = walk(i, next);
				if (chain[chain.length - 1] == i) chain.pop();
				out.push({pixels: chain, closed: true, dot: false});
			}
		for (e in edges) {
			var a = e[0], b = e[e.length - 1], ends = (degree[a] == 1 ? 1 : 0) + (degree[b] == 1 ? 1 : 0);
			var reach = Math.max(dt[a], dt[b]) / 3;
			// (a short chain from an end into a junction: a corner's spur)
			if (ends == 1 && e.length < reach * 1.3) continue;
			// (a chain between junctions next to each other: nothing to draw)
			if (ends == 0 && e.length < 3) continue;
			// (where it runs into a junction, thinning bends it toward the
			// junction's centre: cut back there and carried on straight instead)
			var px = e.copy(), tips:Array<Null<{x:Float, y:Float}>> = [null, null];
			// (a free end too: on a terminal cut on a slant, thinning hooks it toward a corner)
			var half = 0.0;
			for (i in e)
				half = Math.max(half, dt[i] / 3);
			for (end in 0...2) {
				var j = end == 0 ? a : b;
				if (degree[j] != 1 && degree[j] < 3) continue;
				var r = degree[j] == 1 ? half * 0.8 : dt[j] / 3, jx = j % w, jy = Std.int(j / w), cut = false;
				while (px.length > 6) {
					var q = end == 0 ? px[0] : px[px.length - 1];
					if (Math.sqrt(Math.pow(q % w - jx, 2) + Math.pow(Std.int(q / w) - jy, 2)) >= r) break;
					if (end == 0) px.shift() else px.pop();
					cut = true;
				}
				if (!cut) continue;
				var q = end == 0 ? px[0] : px[px.length - 1], back = end == 0 ? px[4] : px[px.length - 5];
				var dx = q % w - back % w, dy = Std.int(q / w) - Std.int(back / w), len = Math.sqrt(dx * dx + dy * dy);
				if (len > 0) tips[end] = {x: q % w + dx / len * r, y: Std.int(q / w) + dy / len * r};
			}
			out.push({pixels: px, closed: false, dot: ends == 2 && e.length < reach * 1.2, start: tips[0], end: tips[1]});
		}
		return out;
	}

	static function median(v:Array<Float>):Float {
		var s = v.copy();
		s.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return s[Std.int(s.length / 2)];
	}

	static inline function min(a:Int, b:Int):Int
		return a < b ? a : b;
}

private typedef Traced = {lines:Array<Line>, widths:Array<Float>, left:Float, right:Float, advance:Float};

// (start, end: an end carried on past its pixels, in pixels)
private typedef Chain = {pixels:Array<Int>, closed:Bool, dot:Bool, ?start:{x:Float, y:Float}, ?end:{x:Float, y:Float}};

private class Collect implements Outline {
	final path:Path;
	final fx:Float->Float;
	final fy:Float->Float;

	public function new(path, fx, fy) {
		this.path = path;
		this.fx = fx;
		this.fy = fy;
	}

	public function moveTo(x:Float, y:Float)
		path.moveTo(fx(x), fy(y));

	public function lineTo(x:Float, y:Float)
		path.lineTo(fx(x), fy(y));

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		path.quadTo(fx(cx), fy(cy), fx(x), fy(y));

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		path.cubicTo(fx(c1x), fy(c1y), fx(c2x), fy(c2y), fx(x), fy(y));

	public function close()
		path.close();
}
