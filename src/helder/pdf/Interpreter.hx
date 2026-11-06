package helder.pdf;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Gradient;
import helder.canvas.Matrix;
import helder.canvas.Paint;
import helder.canvas.Painter;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.pdf.PdfValue;
import helder.pdf.Document;
import helder.pdf.Colors;
import helder.pdf.PdfFont;

// A page's content streams run on a helder.canvas Painter (after leanpdf's
// interpreter, which runs them on Canvas 2D): the graphics state (q, Q,
// cm, line styles, ExtGState's opacity, blend mode and line styles),
// paths (m, l, c, v, y, h, re) filled by either rule, stroked, clipping
// (W, W*), colours in any colour space, shadings (axial and radial as
// gradients, their function sampled), shading and tiling patterns, text
// (its state, Tj, TJ, ', ", the render modes, clipping by text) as the
// fonts' outlines (PdfFont; Type 3's glyph procedures run), image
// XObjects and inline images (PdfImage), form XObjects (their matrix,
// bounding box, a transparency group's opacity as a layer). Operators,
// nesting and images are bounded by PdfLimits; a broken operator is
// skipped, a broken object leaves what it would have drawn out.
class Interpreter {
	final doc:Document;
	final painter:Painter;
	// PDF's user space to the painter's pixels
	final base:Matrix;
	var gs:GState;
	final stack:Array<GState> = [];
	var path = new Path();
	// (the painter's transform made in it: base after the CTM)
	final device_ = new Matrix();
	var pendingClip = 0;
	final operands:Array<PdfValue> = [];
	var ops = 0;
	final fonts = new Map<PdfDict, PdfFont>();
	final paint = new Paint();
	final stroke = new Stroke();
	var depth = 0;
	var textClip:Null<Path> = null;
	// (the text matrix and line matrix)
	var tm = new Matrix();
	var tlm = new Matrix();

	// (text: the characters shown, appended in content order, a space at a gap and a newline at a new line;
	// textOnly: nothing painted, no image decoded: the text alone)
	public var text:Null<StringBuf> = null;
	public var textOnly = false;
	// (collect: the images a page draws, by their cache key and size shown, and nothing drawn: PdfWeb.prepare)
	public var collect:Null<Array<{key:String, dict:PdfDict, value:PdfValue, width:Int, height:Int}>> = null;
	var lastText:Null<Matrix> = null;
	var lastSize = 0.0;

	public function new(doc:Document, painter:Painter, base:Matrix) {
		this.doc = doc;
		this.painter = painter;
		this.base = base;
		gs = new GState();
		stroke.dots = false;
	}

	public function run(content:Bytes, resources:Null<PdfDict>) {
		if (++depth > doc.limits.maxDepth) {
			depth--;
			return;
		}
		var p = new Parser(content, 0, null, doc.limits.maxNesting);
		var level = stack.length;
		while (true) {
			var v = try p.next() catch (e:PdfError) {
				if (e.kind == TooLarge) throw e;
				p.pos++;
				continue;
			}
			if (v != null) {
				if (operands.length < 64) operands.push(v);
				continue;
			}
			var op = p.keyword;
			if (op == "" && p.pos >= p.end) break;
			if (++ops > doc.limits.maxOperators) throw PdfError.tooLarge("past " + doc.limits.maxOperators + " operators");
			if (op == "BI") {
				inlineImage(p, resources);
				operands.resize(0);
				continue;
			}
			try
				exec(op, resources)
			catch (e:PdfError) {
				if (e.kind == TooLarge) throw e;
			}
			operands.resize(0);
		}
		// (saves left open by the stream closed)
		while (stack.length > level)
			popState();
		depth--;
	}

	inline function n(i:Int):Float
		return i < operands.length ? Values.num(operands[i]) : 0;

	inline function last(i:Int):Float
		return operands.length - 1 - i >= 0 ? Values.num(operands[operands.length - 1 - i]) : 0;

	function pushState() {
		if (stack.length > 256) return;
		stack.push(gs.copy());
		painter.save();
	}

	function popState() {
		if (stack.length == 0) return;
		gs = stack.pop();
		painter.restore();
	}

	// the painter's transform: base after the CTM
	function device(?m:Matrix) {
		var t = device_.copyFrom(base).multiply(m ?? gs.ctm);
		painter.setTransform(t.a, t.b, t.c, t.d, t.e, t.f);
	}

	function exec(op:String, res:Null<PdfDict>) {
		switch op {
			case "q": pushState();
			case "Q": popState();
			case "cm": gs.ctm.transform(n(0), n(1), n(2), n(3), n(4), n(5));
			case "w": gs.lineWidth = n(0);
			case "J": gs.cap = Std.int(n(0));
			case "j": gs.join = Std.int(n(0));
			case "M": gs.miter = n(0);
			case "d":
				var a = operands.length > 0 ? Values.nums(operands[0]) : null;
				gs.dash = a != null && a.length > 0 ? a : null;
				gs.dashPhase = n(1);
			case "gs": extGState(res, Values.name(operands[0], ""));
			case "ri" | "i":
			case "m": path.moveTo(n(0), n(1));
			case "l": path.lineTo(n(0), n(1));
			case "c": path.cubicTo(n(0), n(1), n(2), n(3), n(4), n(5));
			case "v": path.cubicTo(path.currentX, path.currentY, n(0), n(1), n(2), n(3));
			case "y": path.cubicTo(n(0), n(1), n(2), n(3), n(2), n(3));
			case "h": path.close();
			case "re":
				var x = n(0), y = n(1), w = n(2), h = n(3);
				path.moveTo(x, y);
				path.lineTo(x + w, y);
				path.lineTo(x + w, y + h);
				path.lineTo(x, y + h);
				path.close();
			case "S": paintPath(false, true, false);
			case "s": path.close(); paintPath(false, true, false);
			case "f" | "F": paintPath(true, false, false);
			case "f*": paintPath(true, false, true);
			case "B": paintPath(true, true, false);
			case "B*": paintPath(true, true, true);
			case "b": path.close(); paintPath(true, true, false);
			case "b*": path.close(); paintPath(true, true, true);
			case "n": paintPath(false, false, false);
			case "W": pendingClip = 1;
			case "W*": pendingClip = 2;
			// colours
			case "CS": gs.strokeSpace = ColorSpace.load(doc, operands[0], res); gs.strokeComps = gs.strokeSpace.initial(); gs.strokePattern = null;
			case "cs": gs.fillSpace = ColorSpace.load(doc, operands[0], res); gs.fillComps = gs.fillSpace.initial(); gs.fillPattern = null;
			case "SC" | "SCN": setColor(false, res);
			case "sc" | "scn": setColor(true, res);
			case "G": gs.strokeSpace = ColorSpace.GRAY; gs.strokeComps = [n(0)]; gs.strokePattern = null;
			case "g": gs.fillSpace = ColorSpace.GRAY; gs.fillComps = [n(0)]; gs.fillPattern = null;
			case "RG": gs.strokeSpace = ColorSpace.RGB; gs.strokeComps = [n(0), n(1), n(2)]; gs.strokePattern = null;
			case "rg": gs.fillSpace = ColorSpace.RGB; gs.fillComps = [n(0), n(1), n(2)]; gs.fillPattern = null;
			case "K": gs.strokeSpace = ColorSpace.CMYK; gs.strokeComps = [n(0), n(1), n(2), n(3)]; gs.strokePattern = null;
			case "k": gs.fillSpace = ColorSpace.CMYK; gs.fillComps = [n(0), n(1), n(2), n(3)]; gs.fillPattern = null;
			case "sh": if (!textOnly) shading(res, Values.name(operands[0], ""));
			case "Do": xobject(res, Values.name(operands[0], ""));
			// text
			case "BT":
				tm = new Matrix();
				tlm = new Matrix();
			case "ET":
				if (textClip != null) {
					device();
					painter.clip(textClip);
					textClip = null;
				}
			case "Tc": gs.charSpacing = n(0);
			case "Tw": gs.wordSpacing = n(0);
			case "Tz": gs.hScale = n(0) / 100;
			case "TL": gs.leading = n(0);
			case "Ts": gs.rise = n(0);
			case "Tr": gs.render = Std.int(n(0));
			case "Tf":
				gs.font = font(res, Values.name(operands[0], ""));
				gs.fontSize = n(1);
			case "Td":
				tlm.translate(n(0), n(1));
				tm.copyFrom(tlm);
			case "TD":
				gs.leading = -n(1);
				tlm.translate(n(0), n(1));
				tm.copyFrom(tlm);
			case "Tm":
				tlm.set(n(0), n(1), n(2), n(3), n(4), n(5));
				tm.copyFrom(tlm);
			case "T*":
				tlm.translate(0, -gs.leading);
				tm.copyFrom(tlm);
			case "Tj": show(Values.str(operands.length > 0 ? operands[0] : PNull), res);
			case "'":
				tlm.translate(0, -gs.leading);
				tm.copyFrom(tlm);
				show(Values.str(operands.length > 0 ? operands[operands.length - 1] : PNull), res);
			case "\"":
				gs.wordSpacing = n(0);
				gs.charSpacing = n(1);
				tlm.translate(0, -gs.leading);
				tm.copyFrom(tlm);
				show(Values.str(operands.length > 2 ? operands[2] : PNull), res);
			case "TJ":
				var a = operands.length > 0 ? Values.arr(operands[0]) : null;
				if (a != null)
					for (x in a)
						switch x {
							case PStr(b): show(b, res);
							case PNum(k):
								var adv = -k / 1000 * gs.fontSize * gs.hScale;
								if (gs.font != null && gs.font.vertical) tm.translate(0, k / 1000 * gs.fontSize) else tm.translate(adv, 0);
							case _:
						}
			case "d0" | "d1":
			case _:
		}
	}

	// the path painted, clipped by when W came first, then cleared
	function paintPath(fill:Bool, strokeIt:Bool, evenOdd:Bool) {
		// (the path cleared for the next: a painter takes it as it is now, keeping none)
		if (textOnly) {
			pendingClip = 0;
			path.clear();
			return;
		}
		device();
		if (fill) {
			if (prepare(true)) painter.fill(path, paint, evenOdd);
		}
		if (strokeIt) {
			if (prepare(false)) {
				setStroke();
				painter.stroke(path, stroke, paint);
			}
		}
		if (pendingClip > 0) {
			device();
			painter.clip(path, pendingClip == 2);
			pendingClip = 0;
		}
		path.clear();
	}

	function setStroke() {
		// (a width of 0, or one thinner than a pixel: the thinnest line the device draws, a pixel, as viewers do)
		var s = device_.copyFrom(base).multiply(gs.ctm).maxScale();
		stroke.width = gs.lineWidth * s >= 1 ? gs.lineWidth : 1 / Math.max(s, 1e-9);
		stroke.cap = gs.cap == 1 ? Cap.round : gs.cap == 2 ? Cap.square : Cap.butt;
		stroke.join = gs.join == 1 ? Join.round : gs.join == 2 ? Join.bevel : Join.miter;
		stroke.miterLimit = gs.miter;
		stroke.dash = gs.dash != null && !Lambda.exists(gs.dash, d -> d < 0) && Lambda.fold(gs.dash, (d, s) -> d + s, 0.0) > 0 ? new Dash(gs.dash, gs.dashPhase) : null;
	}

	// the paint for filling or stroking (false: it paints nothing)
	function prepare(fill:Bool):Bool {
		paint.shader = null;
		paint.blend = gs.blend;
		paint.alpha = fill ? gs.fillAlpha : gs.strokeAlpha;
		var pat = fill ? gs.fillPattern : gs.strokePattern;
		if (pat != null) {
			var sh = pattern(pat, fill);
			if (sh == null) return false;
			paint.shader = sh;
			paint.color = 0xFF000000;
			return true;
		}
		paint.color = fill ? gs.fillSpace.rgb(gs.fillComps) : gs.strokeSpace.rgb(gs.strokeComps);
		return true;
	}

	function setColor(fill:Bool, res:Null<PdfDict>) {
		var space = fill ? gs.fillSpace : gs.strokeSpace;
		if (space.kind == "Pattern") {
			var name = operands.length > 0 ? Values.name(operands[operands.length - 1]) : null;
			if (fill) gs.fillPattern = name else gs.strokePattern = name;
			gs.patternResources = res;
			return;
		}
		var c = [for (v in operands) Values.num(v)];
		if (fill) gs.fillComps = c else gs.strokeComps = c;
	}

	function extGState(res:Null<PdfDict>, name:String) {
		var all = res == null ? null : Values.dict(doc.resolve(res.get("ExtGState")));
		var d = all == null ? null : Values.dict(doc.resolve(all.get(name)));
		if (d == null) return;
		for (k => v0 in d.map) {
			var v = doc.resolve(v0);
			switch k {
				case "CA": gs.strokeAlpha = Values.num(v, 1);
				case "ca": gs.fillAlpha = Values.num(v, 1);
				case "LW": gs.lineWidth = Values.num(v, 1);
				case "LC": gs.cap = Values.int(v);
				case "LJ": gs.join = Values.int(v);
				case "ML": gs.miter = Values.num(v, 10);
				case "D":
					var a = Values.arr(v);
					if (a != null && a.length > 1) {
						gs.dash = Values.nums(doc.resolve(a[0]));
						gs.dashPhase = Values.num(doc.resolve(a[1]));
					}
				case "BM":
					var bm = switch v {
						case PArray(list) if (list.length > 0): Values.name(doc.resolve(list[0]), "Normal");
						case _: Values.name(v, "Normal");
					}
					gs.blend = blendOf(bm);
				case "Font":
					var a = Values.arr(v);
					if (a != null && a.length > 1) {
						var fd = Values.dict(doc.resolve(a[0]));
						if (fd != null) gs.font = fontOf(fd);
						gs.fontSize = Values.num(doc.resolve(a[1]));
					}
				case _:
			}
		}
	}

	static function blendOf(name:String):Null<helder.canvas.Blend.Blender>
		return switch name {
			case "Multiply": helder.canvas.Blend.multiply;
			case "Screen": helder.canvas.Blend.screen;
			case "Overlay": helder.canvas.Blend.overlay;
			case "Darken": helder.canvas.Blend.darken;
			case "Lighten": helder.canvas.Blend.lighten;
			case "ColorDodge": helder.canvas.Blend.colorDodge;
			case "ColorBurn": helder.canvas.Blend.colorBurn;
			case "HardLight": helder.canvas.Blend.hardLight;
			case "SoftLight": helder.canvas.Blend.softLight;
			case "Difference": helder.canvas.Blend.difference;
			case "Exclusion": helder.canvas.Blend.exclusion;
			case "Hue": helder.canvas.Blend.hue;
			case "Saturation": helder.canvas.Blend.saturation;
			case "Color": helder.canvas.Blend.color;
			case "Luminosity": helder.canvas.Blend.luminosity;
			case _: null;
		}

	// ---- fonts and text

	function font(res:Null<PdfDict>, name:String):Null<PdfFont> {
		var all = res == null ? null : Values.dict(doc.resolve(res.get("Font")));
		var d = all == null ? null : Values.dict(doc.resolve(all.get(name)));
		return d == null ? null : fontOf(d);
	}

	function fontOf(d:PdfDict):Null<PdfFont> {
		var f = fonts.get(d);
		if (f == null) {
			f = try new PdfFont(doc, d) catch (e:PdfError) {
				if (e.kind == TooLarge) throw e;
				null;
			}
			if (f == null) return null;
			fonts.set(d, f);
		}
		return f;
	}

	final codeOut = [0, 0];

	function show(s:Null<Bytes>, res:Null<PdfDict>) {
		var f = gs.font;
		if (s == null || f == null) return;
		var fs = gs.fontSize, th = gs.hScale;
		var glyphs = new Path();
		var i = 0;
		var mode = gs.render;
		// (a painter keeping glyphs (the web's): each glyph by its key and transform, a plain fill only)
		var cache:Null<helder.canvas.GlyphCache> = !textOnly && !f.type3 && mode == 0 && Std.isOfType(painter, helder.canvas.GlyphCache) ? cast painter : null;
		if (cache != null) {
			if (!prepare(true) || paint.shader != null) cache = null else cache.glyphs(paint);
		}
		while (i < s.length) {
			f.code(s, i, codeOut);
			var code = codeOut[0], len = codeOut[1];
			i += len;
			// (the text rendering matrix: font size, horizontal scale and rise, then Tm)
			var trm = tm.clone().multiply(new Matrix(fs * th, 0, 0, fs, 0, gs.rise));
			if (text != null) addText(f, code, trm);
			if (textOnly) {} else if (cache != null) {
				var c = code;
				cache.glyph((f.id << 16) | (c & 0xFFFF), () -> f.glyphPath(c), base.clone().multiply(gs.ctm).multiply(trm));
			} else if (f.type3) type3Glyph(f, code, trm) else if (mode != 3 && mode != 7) glyphs.addPath(f.glyphPath(code), trm);
			var w0 = f.width(code) / 1000;
			var space = len == 1 && code == 32 ? gs.wordSpacing : 0;
			if (f.vertical) tm.translate(0, -(w0 * fs + gs.charSpacing + space)) else tm.translate((w0 * fs + gs.charSpacing + space) * th, 0);
		}
		if (f.type3 || textOnly || glyphs.isEmpty()) return;
		device();
		if (mode == 0 || mode == 2 || mode == 4 || mode == 6) if (prepare(true)) painter.fill(glyphs, paint);
		if (mode == 1 || mode == 2 || mode == 5 || mode == 6) if (prepare(false)) {
			setStroke();
			painter.stroke(glyphs, stroke, paint);
		}
		if (mode >= 4) {
			if (textClip == null) textClip = new Path();
			textClip.addPath(glyphs);
		}
	}

	// a code's characters into text: a newline when the baseline moved, a space at a gap of a quarter em
	function addText(f:PdfFont, code:Int, trm:Matrix) {
		var u = f.unicodeOf(code);
		if (u == "") return;
		var m = gs.ctm.clone().multiply(trm), size = Math.sqrt(m.c * m.c + m.d * m.d);
		if (lastText != null) {
			var dy = Math.abs(m.f - lastText.f), dx = m.e - lastText.e;
			if (dy > Math.max(size, lastSize) * 0.5) text.add("\n") else if (dx > Math.max(size, lastSize) * 0.25 && u != " ") text.add(" ");
		}
		text.add(u);
		// (where the next would start: past this one's advance)
		lastText = m.clone().multiply(new Matrix(1, 0, 0, 1, f.width(code) / 1000, 0));
		lastSize = size;
	}

	function type3Glyph(f:PdfFont, code:Int, trm:Matrix) {
		var name = f.glyphName(code);
		if (name == null || f.charProcs == null) return;
		var proc = doc.resolve(f.charProcs.get(name));
		var data = try doc.stream(proc) catch (_:PdfError) null;
		if (data == null) return;
		pushState();
		gs.ctm = gs.ctm.clone().multiply(trm).multiply(f.matrix);
		var saveTm = tm.clone(), saveTlm = tlm.clone(), savePath = path;
		path = new Path();
		run(data, f.resources);
		path = savePath;
		tm = saveTm;
		tlm = saveTlm;
		popState();
	}

	// ---- shadings and patterns

	function shadingGradient(sd:PdfDict, sv:PdfValue):Null<Gradient> {
		var type = Values.int(sd.get("ShadingType"));
		if (type != 2 && type != 3) return null;
		var coords = Values.nums(doc.resolve(sd.get("Coords")));
		if (coords == null) return null;
		var cs = ColorSpace.load(doc, sd.get("ColorSpace"), null);
		var fn = PdfFunction.load(doc, sd.get("Function"));
		var domain = Values.nums(doc.resolve(sd.get("Domain"))) ?? [0.0, 1];
		var g:Gradient = type == 2 ? new LinearGradient(coords[0], coords[1], coords[2], coords[3]) : new RadialGradient(coords[0], coords[1], coords[2],
			coords[3], coords[4], coords[5]);
		// (the function sampled: 33 stops)
		for (k in 0...33) {
			var t = k / 32;
			g.addStop(t, cs.rgb(fn.eval([domain[0] + t * (domain[1] - domain[0])])));
		}
		return g;
	}

	function shading(res:Null<PdfDict>, name:String) {
		var all = res == null ? null : Values.dict(doc.resolve(res.get("Shading")));
		var sv = all == null ? PNull : doc.resolve(all.get(name));
		var sd = Values.dict(sv);
		if (sd == null) return;
		var g = shadingGradient(sd, sv);
		if (g == null) return;
		// (all of the clip: a big rectangle in user space)
		device();
		var p = new Path();
		var inv = new Matrix();
		if (!base.clone().multiply(gs.ctm).invertInto(inv)) return;
		var big = new Path();
		big.rect(-1e5, -1e5, 2e5, 2e5);
		paint.shader = g;
		paint.alpha = gs.fillAlpha;
		paint.blend = gs.blend;
		painter.setTransform(1, 0, 0, 1, 0, 0);
		var m = base.clone().multiply(gs.ctm);
		g.matrix.copyFrom(m);
		painter.fill(big, paint);
		g.matrix.identity();
	}

	// a pattern's shader (its matrix from the default space of the page: base after the pattern's)
	function pattern(name:String, fill:Bool):Null<helder.canvas.Paint.Shader> {
		var res = gs.patternResources;
		var all = res == null ? null : Values.dict(doc.resolve(res.get("Pattern")));
		var pv = all == null ? PNull : doc.resolve(all.get(name));
		var pd = Values.dict(pv);
		if (pd == null) return null;
		var pm = Values.nums(doc.resolve(pd.get("Matrix"))) ?? [1.0, 0, 0, 1, 0, 0];
		var m = new Matrix(pm[0], pm[1], pm[2], pm[3], pm[4], pm[5]);
		// (the shader's space in the painter's user space: the CTM's inverse after the page's default)
		var inv = new Matrix();
		if (!gs.ctm.invertInto(inv)) return null;
		var place = inv.multiply(gs.baseCtm).multiply(m);
		var type = Values.int(pd.get("PatternType"));
		if (type == 2) {
			var sv = doc.resolve(pd.get("Shading")), sd = Values.dict(sv);
			if (sd == null) return null;
			var g = shadingGradient(sd, sv);
			if (g == null) return null;
			g.matrix.copyFrom(place);
			return g;
		}
		// a tiling pattern: its cell drawn at the device's scale (by the painter's own kind), repeated
		var bbox = Values.nums(doc.resolve(pd.get("BBox"))) ?? [0.0, 0, 1, 1];
		var xs = Math.abs(Values.num(doc.resolve(pd.get("XStep")), bbox[2] - bbox[0])), ys = Math.abs(Values.num(doc.resolve(pd.get("YStep")), bbox[3] - bbox[1]));
		if (xs <= 0 || ys <= 0) return null;
		var scale = base.clone().multiply(gs.baseCtm).multiply(m).maxScale();
		var cw = Std.int(Math.max(1, Math.min(2048, Math.ceil(xs * scale)))), ch = Std.int(Math.max(1, Math.min(2048, Math.ceil(ys * scale))));
		var cell = painter.offscreen(cw, ch);
		var sub = new Interpreter(doc, cell, new Matrix(cw / xs, 0, 0, -ch / ys, -bbox[0] * cw / xs, ch + bbox[1] * ch / ys));
		sub.depth = depth + 1;
		if (Values.int(pd.get("PaintType"), 1) == 2) {
			sub.gs.fillSpace = gs.fillSpace;
			sub.gs.fillComps = gs.fillComps;
		}
		try sub.run(doc.stream(pv), Values.dict(doc.resolve(pd.get("Resources")))) catch (e:PdfError) {
			if (e.kind == TooLarge) throw e;
		}
		var pat = new helder.canvas.Pattern(cell.snapshot(), true, true, true);
		// (the cell's pixels to pattern space, flipped as the cell was drawn)
		pat.matrix.copyFrom(place.multiply(new Matrix(xs / cw, 0, 0, -ys / ch, bbox[0], bbox[1] + ys)));
		return pat;
	}

	// ---- XObjects

	function xobject(res:Null<PdfDict>, name:String) {
		var all = res == null ? null : Values.dict(doc.resolve(res.get("XObject")));
		var v = all == null ? PNull : doc.resolve(all.get(name));
		var d = Values.dict(v);
		if (d == null) return;
		switch Values.name(d.get("Subtype")) {
			case "Image":
				var fill = gs.fillSpace.kind == "Pattern" ? 0xFF000000 : gs.fillSpace.rgb(gs.fillComps);
				var s = shownSize();
				// (the document's cache: by its reference and the size shown; a mask's by its colour too)
				var key = switch all.get(name) {
					case PRef(n, g): '$n $g@${s[0]}x${s[1]}' + (Values.bool(doc.resolve(d.has("ImageMask") ? d.get("ImageMask") : d.get("IM"))) ? "#" + fill : "");
					case _: null;
				}
				if (collect != null) {
					if (key != null) collect.push({key: key, dict: d, value: v, width: s[0], height: s[1]});
					return;
				}
				if (textOnly) return;
				var interpolate = Values.bool(doc.resolve(d.get("Interpolate")));
				var cached:Dynamic = key == null ? null : doc.images.get(key);
				if (cached != null && Std.isOfType(cached, Bitmap)) {
					drawImage(cached, interpolate);
					return;
				}
				if (cached != null && Std.isOfType(cached, helder.canvas.HandleImages.ImageHandle) && Std.isOfType(painter, helder.canvas.HandleImages)) {
					var hi:helder.canvas.HandleImages.ImageHandle = cached;
					var hp:helder.canvas.HandleImages = cast painter;
					place(hi.width, hi.height, interpolate);
					hp.drawHandle(hi.handle, 0, 0, hi.width, hi.height, 0, 0, 1, 1, paint, smoothNow);
					return;
				}
				var b = PdfImage.decode(doc, d, v, res, withAlpha(fill, 1), null, s[0], s[1]);
				if (key != null) doc.images.put(key, b, b.width * b.height * 4);
				drawImage(b, interpolate);
			case "Form": form(d, v, res);
			case _:
		}
	}

	// the page's annotations, each by its normal appearance (/AP /N, by /AS when it has states) mapped
	// into its /Rect, as viewers print them; hidden ones (/F's Hidden, NoView) and popups left out
	public function annotations(annots:PdfValue, res:Null<PdfDict>) {
		var list = Values.arr(doc.resolve(annots));
		if (list == null || textOnly) return;
		for (av in list) {
			var a = Values.dict(doc.resolve(av));
			if (a == null || Values.name(a.get("Subtype")) == "Popup" || Values.int(doc.resolve(a.get("F"))) & (2 | 32) != 0) continue;
			var ap = Values.dict(doc.resolve(a.get("AP")));
			var n = ap == null ? PNull : doc.resolve(ap.get("N"));
			switch n {
				case PStream(_, _):
				case PDict(states): n = doc.resolve(states.get(Values.name(doc.resolve(a.get("AS")), "Off")));
				case _: continue;
			}
			var d = Values.dict(n), rect = Values.nums(doc.resolve(a.get("Rect")));
			if (d == null || rect == null || rect.length != 4) continue;
			var bbox = Values.nums(doc.resolve(d.get("BBox"))) ?? [0.0, 0, 1, 1];
			var fm = Values.nums(doc.resolve(d.get("Matrix")));
			var m = fm != null && fm.length == 6 ? new Matrix(fm[0], fm[1], fm[2], fm[3], fm[4], fm[5]) : new Matrix();
			// (the box through its matrix, its bounds onto the rectangle)
			var xs = [], ys = [];
			for (c in [[bbox[0], bbox[1]], [bbox[2], bbox[1]], [bbox[0], bbox[3]], [bbox[2], bbox[3]]]) {
				xs.push(m.a * c[0] + m.c * c[1] + m.e);
				ys.push(m.b * c[0] + m.d * c[1] + m.f);
			}
			var x0 = Lambda.fold(xs, Math.min, xs[0]), x1 = Lambda.fold(xs, Math.max, xs[0]);
			var y0 = Lambda.fold(ys, Math.min, ys[0]), y1 = Lambda.fold(ys, Math.max, ys[0]);
			if (x1 - x0 <= 0 || y1 - y0 <= 0) continue;
			var rx0 = Math.min(rect[0], rect[2]), ry0 = Math.min(rect[1], rect[3]);
			var sx = (Math.max(rect[0], rect[2]) - rx0) / (x1 - x0), sy = (Math.max(rect[1], rect[3]) - ry0) / (y1 - y0);
			pushState();
			gs.ctm.transform(sx, 0, 0, sy, rx0 - x0 * sx, ry0 - y0 * sy);
			try form(d, n, res) catch (e:PdfError) {
				if (e.kind == TooLarge) throw e;
			}
			popState();
		}
	}

	// a Form XObject: its matrix, clipped to its box, its own resources, a transparency group apart
	function form(d:PdfDict, v:PdfValue, res:Null<PdfDict>) {
		switch v {
			case _:
				if (depth >= doc.limits.maxDepth) return;
				var content = doc.stream(v);
				var fm = Values.nums(doc.resolve(d.get("Matrix")));
				var bbox = Values.nums(doc.resolve(d.get("BBox")));
				var group = Values.dict(doc.resolve(d.get("Group")));
				pushState();
				if (fm != null && fm.length == 6) gs.ctm.transform(fm[0], fm[1], fm[2], fm[3], fm[4], fm[5]);
				if (bbox != null && bbox.length == 4) {
					var clip = new Path();
					clip.rect(bbox[0], bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]);
					device();
					painter.clip(clip);
				}
				// (a transparency group at an opacity: drawn apart, composited once)
				var layered = group != null && (gs.fillAlpha < 1 || gs.blend != null);
				if (layered) {
					painter.saveLayer(gs.fillAlpha, gs.blend);
					gs.fillAlpha = 1;
					gs.strokeAlpha = 1;
					gs.blend = null;
				}
				var fr = Values.dict(doc.resolve(d.get("Resources"))) ?? res;
				var saveBase = gs.baseCtm;
				run(content, fr);
				if (layered) painter.restore();
				popState();
			case _:
		}
	}

	static inline function withAlpha(c:Int, a:Float):Int
		return (Std.int(((c >>> 24) & 255) * a) << 24) | (c & 0xFFFFFF);

	// an image into the unit square of the CTM (its first row at the top)
	// the pixels an image (the unit square through the CTM) covers on the device, a side each
	function shownSize():Array<Int> {
		var m = base.clone().multiply(gs.ctm);
		return [Std.int(Math.ceil(Math.sqrt(m.a * m.a + m.b * m.b))), Std.int(Math.ceil(Math.sqrt(m.c * m.c + m.d * m.d)))];
	}

	function drawImage(b:Bitmap, interpolate = false) {
		place(b.width, b.height, interpolate);
		painter.drawImage(b, 0, 0, b.width, b.height, 0, 0, 1, 1, paint, smoothNow);
	}

	var smoothNow = true;

	// the transform, paint and smoothing for an image of w x h samples in the unit square
	function place(width:Int, height:Int, interpolate:Bool) {
		var m = gs.ctm.clone().multiply(new Matrix(1, 0, 0, -1, 0, 1));
		device(m);
		// (smoothed when asked, or up to 4/3 of a pixel a sample, as pdf.js does (96 / 72); an image
		// enlarged more shows its samples, as pdf.js and Acrobat do)
		var px = base.clone().multiply(m);
		var sx = Math.sqrt(px.a * px.a + px.b * px.b) / width, sy = Math.sqrt(px.c * px.c + px.d * px.d) / height;
		smoothNow = interpolate || (sx <= 4 / 3 && sy <= 4 / 3);
		paint.shader = null;
		paint.alpha = gs.fillAlpha;
		paint.blend = gs.blend;
	}

	function inlineImage(p:Parser, res:Null<PdfDict>) {
		var d = new PdfDict();
		while (true) {
			var k = p.next();
			if (k == null) break;
			switch k {
				case PName(name):
					var v = p.next();
					if (v == null) break;
					// (abbreviated names: those of a colour space and a filter expanded)
					var full = switch name {
						case "BPC": "BitsPerComponent";
						case "CS": "ColorSpace";
						case "D": "Decode";
						case "DP": "DecodeParms";
						case "F": "Filter";
						case "H": "Height";
						case "IM": "ImageMask";
						case "I": "Interpolate";
						case "W": "Width";
						case _: name;
					}
					d.set(full, expand(v));
				case _:
			}
		}
		if (p.keyword != "ID") return;
		var s = p.pos + 1, e = s;
		// (EI after whitespace and before whitespace or the end)
		while (e + 2 < p.end) {
			if (Parser.isWhite(p.b.get(e)) && p.b.get(e + 1) == "E".code && p.b.get(e + 2) == "I".code
				&& (e + 3 >= p.end || Parser.isWhite(p.b.get(e + 3)) || Parser.isDelim(p.b.get(e + 3))))
				break;
			e++;
		}
		var data = p.b.sub(s, Std.int(Math.max(0, e - s)));
		p.pos = e + 3;
		if (!textOnly) try {
			var fill = gs.fillSpace.kind == "Pattern" ? 0xFF000000 : gs.fillSpace.rgb(gs.fillComps);
			var s = shownSize();
			drawImage(PdfImage.decode(doc, d, PNull, res, fill, data, s[0], s[1]), Values.bool(d.get("Interpolate")));
		} catch (e:PdfError) {
			if (e.kind == TooLarge) throw e;
		}
	}

	static function expand(v:PdfValue):PdfValue
		return switch v {
			case PName("G"): PName("DeviceGray");
			case PName("RGB"): PName("DeviceRGB");
			case PName("CMYK"): PName("DeviceCMYK");
			case PName("AHx"): PName("ASCIIHexDecode");
			case PName("A85"): PName("ASCII85Decode");
			case PName("Fl"): PName("FlateDecode");
			case PName("RL"): PName("RunLengthDecode");
			case PName("DCT"): PName("DCTDecode");
			case PName("LZW"): PName("LZWDecode");
			case PArray(a): PArray([for (x in a) expand(x)]);
			case _: v;
		}
}

// The graphics state PDF's q and Q keep (the clip is the painter's)
class GState {
	public var ctm = new Matrix();
	// (the CTM where the page began: a pattern's space)
	public var baseCtm = new Matrix();
	public var lineWidth = 1.0;
	public var cap = 0;
	public var join = 0;
	public var miter = 10.0;
	public var dash:Null<Array<Float>> = null;
	public var dashPhase = 0.0;
	public var fillSpace = ColorSpace.GRAY;
	public var strokeSpace = ColorSpace.GRAY;
	public var fillComps:Array<Float> = [0];
	public var strokeComps:Array<Float> = [0];
	public var fillPattern:Null<String> = null;
	public var strokePattern:Null<String> = null;
	public var patternResources:Null<PdfDict> = null;
	public var fillAlpha = 1.0;
	public var strokeAlpha = 1.0;
	public var blend:Null<helder.canvas.Blend.Blender> = null;
	public var font:Null<PdfFont> = null;
	public var fontSize = 0.0;
	public var charSpacing = 0.0;
	public var wordSpacing = 0.0;
	public var hScale = 1.0;
	public var leading = 0.0;
	public var rise = 0.0;
	public var render = 0;

	public function new() {}

	public function copy():GState {
		var g = new GState();
		g.ctm = ctm.clone();
		g.baseCtm = baseCtm;
		g.lineWidth = lineWidth;
		g.cap = cap;
		g.join = join;
		g.miter = miter;
		g.dash = dash;
		g.dashPhase = dashPhase;
		g.fillSpace = fillSpace;
		g.strokeSpace = strokeSpace;
		g.fillComps = fillComps;
		g.strokeComps = strokeComps;
		g.fillPattern = fillPattern;
		g.strokePattern = strokePattern;
		g.patternResources = patternResources;
		g.fillAlpha = fillAlpha;
		g.strokeAlpha = strokeAlpha;
		g.blend = blend;
		g.font = font;
		g.fontSize = fontSize;
		g.charSpacing = charSpacing;
		g.wordSpacing = wordSpacing;
		g.hScale = hScale;
		g.leading = leading;
		g.rise = rise;
		g.render = render;
		return g;
	}
}
